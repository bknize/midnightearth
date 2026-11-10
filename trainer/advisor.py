"""The plan advisor (plan P7, P8, P11; spec R17 to R22).

At a block boundary: start llama-server, wait for /health, post one chat completion with a
JSON-schema reply, stop the server (always), write the record, and fall back to a known plan
when anything goes wrong. Knob bounds and trials are `knobs.validate`'s job, not this module's."""
import atexit
import hashlib
import json
import subprocess
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Set, Tuple

from trainer import knobs, store

DEFAULT_SERVER_ARGS: List[str] = ["-c", "40960", "-np", "4", "-fa", "on", "-ctk", "q8_0",
                                  "-ctv", "q8_0", "--jinja"]
HISTORY_ENTRIES = 8
HEALTH_POLL_S = 1.0
STOP_WAIT_S = 20.0
ABANDON_POLL_S = 0.2
REPLY_MAX_TOKENS = 2048  # a reply is a few hundred tokens

_LIVE: Set[Any] = set()  # llama-server children not yet stopped; the atexit hook ends them
_LIVE_LOCK = threading.Lock()


def _kill_live() -> None:
    with _LIVE_LOCK:
        handles = list(_LIVE)
    for handle in handles:
        try:
            handle.terminate()
        except OSError:
            pass


atexit.register(_kill_live)


class Abandoned(Exception):
    """The caller's stop event was set while the advisor waited."""

SYSTEM_TEXT = (
    "You plan the next training block of a card-game bot. Each block labels positions with a "
    "search (the run), then fits a linear evaluation to the labels. The goal is a fit that beats "
    "the current champion in the judge's play-outs. Reply with a JSON object "
    '{"plan": {<knob>: <value>, ...}, "reason": "<why>"}. Set only the knobs you want to '
    "change; the others keep the last plan's value. Never set a pinned knob. Prefer values "
    "inside the bounds; a value outside them is only run as a single trial. The knobs:\n"
    "- generator: how positions are produced, random or linear (the champion's weights).\n"
    "- generator_weights: the fit that drives the generator when it is linear: \"champion\" or "
    "a fit id.\n"
    "- rollout: the play-out policy inside the labelling search, random or linear.\n"
    "- rollout_weights: the fit behind a linear rollout: \"champion\" or a fit id.\n"
    "- positions: how many positions to label; more is slower and gives a steadier fit.\n"
    "- determinizations: hidden-information samples per position; more is slower and less "
    "noisy.\n"
    "- k: how many top moves the search keeps per position.\n"
    "- workers: parallel labelling workers.\n"
    "- l2: ridge strength of the fit; higher shrinks the weights, lower may overfit.\n"
    "- fit_iterations: optimiser iterations of the fit.\n"
    "- holdout: the fraction of labels held out to measure agreement."
)

REPLY_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "plan": {"type": "object", "properties": {name: {} for name in knobs.KNOBS},
                 "additionalProperties": False},
        "reason": {"type": "string"},
    },
    "required": ["plan", "reason"],
    "additionalProperties": False,
}


@dataclass
class AdvisorConfig:
    server_path: str = ""
    model_path: str = ""
    host: str = "127.0.0.1"
    port: int = 8080
    server_args: List[str] = field(default_factory=lambda: list(DEFAULT_SERVER_ARGS))
    health_timeout_s: float = 300.0
    reply_timeout_s: float = 300.0
    model_name: str = ""

    @staticmethod
    def from_dict(d: Any) -> "AdvisorConfig":
        if not isinstance(d, dict):
            raise ValueError("advisor config: expected an object")
        cfg = AdvisorConfig()
        unknown = sorted(set(d) - set(cfg.__dict__))
        if unknown:
            raise ValueError("advisor config: unknown fields: " + ", ".join(unknown))
        for name in ("server_path", "model_path", "host", "model_name"):
            if name in d:
                if not isinstance(d[name], str):
                    raise ValueError("advisor config: %s must be a string" % name)
                setattr(cfg, name, d[name])
        if "port" in d:
            if isinstance(d["port"], bool) or not isinstance(d["port"], int) or d["port"] < 0:
                raise ValueError("advisor config: port must be a non-negative integer")
            cfg.port = d["port"]
        for name in ("health_timeout_s", "reply_timeout_s"):
            if name in d:
                v = d[name]
                if isinstance(v, bool) or not isinstance(v, (int, float)) or v <= 0:
                    raise ValueError("advisor config: %s must be a positive number" % name)
                setattr(cfg, name, float(v))
        if "server_args" in d:
            args = d["server_args"]
            if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
                raise ValueError("advisor config: server_args must be a list of strings")
            cfg.server_args = list(args)
        if not cfg.model_name and cfg.model_path:
            cfg.model_name = Path(cfg.model_path.replace("\\", "/")).name
        return cfg


def load_config(path: Any) -> AdvisorConfig:
    """Read `config.json`; a missing file is FileNotFoundError, a bad one ValueError."""
    with open(path, "r", encoding="utf-8") as fh:
        try:
            raw = json.load(fh)
        except json.JSONDecodeError as exc:
            raise ValueError("advisor config: not JSON: %s" % exc)
    return AdvisorConfig.from_dict(raw)


def default_plan(has_champion: bool) -> Dict[str, Any]:
    """P11's DEFAULT_PLAN; with no champion the rollout is random and has no weights."""
    plan = knobs.plan_defaults()
    plan.update({"generator": "random", "rollout": "linear", "rollout_weights": "champion",
                 "positions": 1000, "determinizations": 16, "k": 8, "workers": 16})
    if not has_champion:
        plan.update({"rollout": "random", "rollout_weights": ""})
    return plan


DEFAULT_PLAN: Dict[str, Any] = default_plan(True)


def fallback_plan(entries: Sequence[Dict[str, Any]],
                  has_champion: bool) -> Tuple[Dict[str, Any], str]:
    """The plan of the last full block that changed the champion, else the default plan."""
    for entry in reversed(list(entries)):
        if entry.get("kind") == "full" \
                and entry.get("champion_after") != entry.get("champion_before") \
                and isinstance(entry.get("plan"), dict):
            return dict(entry["plan"]), "plan of block %s" % entry.get("block")
    return default_plan(has_champion), "default plan"


def _figures(entry: Dict[str, Any]) -> Dict[str, Any]:
    its: List[Dict[str, Any]] = []
    for it in entry.get("iterations") or []:
        if not isinstance(it, dict):
            continue
        its.append({
            "positions": it.get("positions"), "labels": it.get("labels"),
            "label_seconds": it.get("label_seconds"),
            "agreement_fitted": it.get("agreement_fitted"),
            "agreement_heldout": it.get("agreement_heldout"),
            "judge_random": it.get("judge_random"), "judge_champion": it.get("judge_champion"),
        })
    return {
        "block": entry.get("block"), "kind": entry.get("kind"), "status": entry.get("status"),
        "plan": entry.get("plan"), "iterations": its,
        "champion_changed": entry.get("champion_after") != entry.get("champion_before"),
        "fault": entry.get("fault", ""),
    }


def build_prompt(entries: Sequence[Dict[str, Any]], bounds: Dict[str, List[Any]],
                 extras: Dict[str, List[Any]], pins: Dict[str, Any], notes: Sequence[str],
                 plateau: bool, last_plan: Dict[str, Any]) -> List[Dict[str, str]]:
    context = {
        "bounds": bounds, "allowed_extras": extras, "pinned_knobs_do_not_set": dict(pins),
        "steering_notes": list(notes), "plateau": bool(plateau), "last_plan": last_plan,
        "recent_blocks": [_figures(e) for e in list(entries)[-HISTORY_ENTRIES:]],
    }
    user = "Plan the next block. Context:\n" + json.dumps(context, sort_keys=True,
                                                          separators=(",", ":"))
    return [{"role": "system", "content": SYSTEM_TEXT}, {"role": "user", "content": user}]


def prompt_digest(messages: Sequence[Dict[str, Any]]) -> str:
    text = json.dumps(list(messages), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_reply(text: str, pins: Any = ()) -> Tuple[Optional[Dict[str, Any]], str]:
    """(reply, "") when valid, else (None, the problem)."""
    try:
        obj = json.loads(text)
    except (ValueError, TypeError) as exc:
        return None, "reply is not JSON: %s" % exc
    if not isinstance(obj, dict):
        return None, "reply is not an object"
    plan = obj.get("plan")
    if not isinstance(plan, dict):
        return None, "reply has no plan object"
    if not isinstance(obj.get("reason"), str):
        return None, "reply has no reason string"
    for name in plan:
        if name not in knobs.KNOBS:
            return None, "reply names an unknown knob: %s" % name
        if name in pins:
            return None, "reply sets a pinned knob: %s" % name
    return obj, ""


@dataclass
class Advice:
    plan: Dict[str, Any]
    reason: str = ""
    source: str = "fallback"
    fallback_reason: str = ""
    model: str = ""
    prompt_digest: str = ""
    seconds: float = 0.0


def _default_launch(log_path: Path) -> Callable[[List[str]], Any]:
    def launch(argv: List[str]) -> Any:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "ab") as log:
            return subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT)
    return launch


def _default_http(method: str, url: str, body: Optional[bytes],
                  timeout: float) -> Tuple[int, str]:
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return int(resp.status), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return int(exc.code), exc.read().decode("utf-8", "replace")


class Advisor:
    def __init__(self, config: AdvisorConfig, data_dir: Any,
                 launch: Optional[Callable[[List[str]], Any]] = None,
                 http: Optional[Callable[[str, str, Optional[bytes], float],
                                         Tuple[int, str]]] = None,
                 clock: Optional[Callable[[], float]] = None,
                 sleep: Optional[Callable[[float], None]] = None) -> None:
        self.config = config
        self.dir = Path(data_dir) / "autopilot" / "advisor"
        self.launch = launch or _default_launch(self.dir / "llama-server.log")
        self.http = http or _default_http
        self.clock = clock or time.monotonic
        self.sleep = sleep or time.sleep
        self._handle: Any = None

    def close(self) -> None:
        """Terminate the llama-server child if there is one (safe from another thread)."""
        handle = self._handle
        if handle is not None:
            self._stop(handle)

    @staticmethod
    def default_plan(has_champion: bool) -> Dict[str, Any]:
        return default_plan(has_champion)

    def _argv(self) -> List[str]:
        c = self.config
        return [c.server_path, "-m", c.model_path, "--host", c.host,
                "--port", str(c.port)] + list(c.server_args)

    def _url(self, path: str) -> str:
        return "http://%s:%d%s" % (self.config.host, self.config.port, path)

    def _wait_healthy(self, handle: Any, stop: Optional[threading.Event] = None) -> str:
        deadline = self.clock() + self.config.health_timeout_s
        while True:
            if stop is not None and stop.is_set():
                raise Abandoned()
            if handle.poll() is not None:
                return "server exited before it was healthy"
            try:
                status, _ = self.http("GET", self._url("/health"), None, 5.0)
                if status == 200:
                    return ""
            except OSError:
                pass
            if self.clock() >= deadline:
                return "server not healthy within %ss" % self.config.health_timeout_s
            self.sleep(HEALTH_POLL_S)

    def _post(self, body: bytes, stop: Optional[threading.Event]) -> Tuple[int, str]:
        """The chat request; with a stop event it runs on a helper thread that is abandoned
        (not waited for) the moment the event is set."""
        url = self._url("/v1/chat/completions")
        timeout = self.config.reply_timeout_s
        if stop is None:
            return self.http("POST", url, body, timeout)
        box: Dict[str, Any] = {}

        def work() -> None:
            try:
                box["reply"] = self.http("POST", url, body, timeout)
            except BaseException as exc:  # handed to the waiting thread
                box["error"] = exc

        worker = threading.Thread(target=work, daemon=True)
        worker.start()
        while worker.is_alive():
            worker.join(ABANDON_POLL_S)
            if stop.is_set():
                raise Abandoned()
        if "error" in box:
            raise box["error"]
        reply: Tuple[int, str] = box["reply"]
        return reply

    def _ask(self, messages: List[Dict[str, str]], pins: Any, raws: List[str],
             stop: Optional[threading.Event] = None) -> Tuple[Optional[Dict[str, Any]], str]:
        body = json.dumps({
            "messages": messages, "temperature": 0.2,
            # No thinking: the reply is one small JSON object, and a thinking model (Qwen3.5 on
            # the PC) used the whole per-slot context on it and returned nothing (T14).
            "chat_template_kwargs": {"enable_thinking": False}, "max_tokens": REPLY_MAX_TOKENS,
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "plan_reply", "strict": True,
                                                "schema": REPLY_SCHEMA}},
        }).encode("utf-8")
        problem = ""
        for _attempt in range(2):
            try:
                status, text = self._post(body, stop)
            except OSError as exc:  # timeouts and connection errors
                return None, "request failed: %s" % (str(exc) or type(exc).__name__)
            if status != 200:
                return None, "HTTP %d" % status
            finish = ""
            try:
                choice = json.loads(text)["choices"][0]
                content = choice["message"]["content"]
                finish = str(choice.get("finish_reason") or "")
            except (ValueError, KeyError, IndexError, TypeError, AttributeError):
                content = text
            content = content if isinstance(content, str) else json.dumps(content)
            raws.append(content)
            reply, problem = parse_reply(content, pins)
            if reply is not None:
                return reply, ""
            if not content.strip():
                problem = "empty reply (finish_reason %s)" % (finish or "unknown")
        return None, "invalid reply twice: " + problem

    def _stop(self, handle: Any) -> None:
        with _LIVE_LOCK:
            _LIVE.discard(handle)
        if self._handle is handle:
            self._handle = None
        try:
            handle.terminate()
            try:
                handle.wait(STOP_WAIT_S)
            except subprocess.TimeoutExpired:
                handle.kill()
                handle.wait(STOP_WAIT_S)
        except OSError:
            pass

    def advise(self, block: int, entries: Sequence[Dict[str, Any]],
               bounds: Dict[str, List[Any]], extras: Dict[str, List[Any]],
               pins: Dict[str, Any], notes: Sequence[str], plateau: bool,
               last_plan: Dict[str, Any], has_champion: bool,
               stop: Optional[threading.Event] = None) -> Advice:
        start = self.clock()
        c = self.config
        messages = build_prompt(entries, bounds, extras, pins, notes, plateau, last_plan)
        digest = prompt_digest(messages)
        raws: List[str] = []
        reply: Optional[Dict[str, Any]] = None
        problem = ""
        if not c.server_path:
            problem = "no server_path in the advisor config"
        elif not c.model_path:
            problem = "no model_path in the advisor config"
        else:
            handle: Any = None
            try:
                handle = self.launch(self._argv())
                self._handle = handle
                with _LIVE_LOCK:
                    _LIVE.add(handle)
                problem = self._wait_healthy(handle, stop)
                if not problem:
                    reply, problem = self._ask(messages, pins, raws, stop)
            except Abandoned:
                problem = "advisor stopped by a shutdown or stop"
            except (OSError, ValueError) as exc:
                problem = "advisor failed: %s" % exc
            finally:
                if handle is not None:
                    self._stop(handle)
        advice = self._finish(reply, problem, entries, has_champion)
        advice.model = c.model_name
        advice.prompt_digest = digest
        advice.seconds = max(0.0, self.clock() - start)
        self._record(block, advice, messages, raws)
        return advice

    def _finish(self, reply: Optional[Dict[str, Any]], problem: str,
                entries: Sequence[Dict[str, Any]], has_champion: bool) -> Advice:
        if reply is not None:
            return Advice(plan=dict(reply["plan"]), reason=str(reply["reason"]),
                          source="advisor")
        plan, which = fallback_plan(entries, has_champion)
        return Advice(plan=plan, source="fallback",
                      fallback_reason="%s (fell back to the %s)" % (problem, which))

    def _record(self, block: int, advice: Advice, messages: List[Dict[str, str]],
                raws: List[str]) -> None:
        record = {
            "block": block, "model": advice.model, "prompt_digest": advice.prompt_digest,
            "messages": messages, "raw_replies": raws, "outcome": advice.source,
            "plan": advice.plan, "reason": advice.reason,
            "fallback_reason": advice.fallback_reason, "seconds": advice.seconds,
        }
        try:
            self.dir.mkdir(parents=True, exist_ok=True)
            store.write_atomic(self.dir / ("%d.json" % block),
                               json.dumps(record, sort_keys=True, indent=1) + "\n")
        except OSError:
            pass


class FileAdvisor:
    """An `Advisor` whose config is read from `<data>/autopilot/config.json` at every call, so
    an edit takes effect at the next block boundary. A missing or invalid config gives the
    fallback plan with the reason; no server is started."""

    def __init__(self, data_dir: Any, **advisor_kwargs: Any) -> None:
        self.data_dir = Path(data_dir)
        self.path = self.data_dir / "autopilot" / "config.json"
        self.kwargs = advisor_kwargs
        self._current: Optional[Advisor] = None

    def close(self) -> None:
        """Terminate the llama-server child of the advise call in flight, if any."""
        current = self._current
        if current is not None:
            current.close()

    @staticmethod
    def default_plan(has_champion: bool) -> Dict[str, Any]:
        return default_plan(has_champion)

    def advise(self, block: int, entries: Sequence[Dict[str, Any]],
               bounds: Dict[str, List[Any]], extras: Dict[str, List[Any]],
               pins: Dict[str, Any], notes: Sequence[str], plateau: bool,
               last_plan: Dict[str, Any], has_champion: bool,
               stop: Optional[threading.Event] = None) -> Advice:
        try:
            config = load_config(self.path)
        except FileNotFoundError:
            problem = "no advisor config at %s" % self.path
        except (OSError, ValueError) as exc:
            problem = str(exc)
        else:
            self._current = Advisor(config, self.data_dir, **self.kwargs)
            return self._current.advise(block, entries, bounds, extras, pins, notes, plateau,
                                        last_plan, has_champion, stop)
        plan, which = fallback_plan(entries, has_champion)
        return Advice(plan=plan, source="fallback",
                      fallback_reason="%s (fell back to the %s)" % (problem, which))
