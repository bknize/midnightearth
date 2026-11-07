"""A stand-in play-out worker that speaks the protocol (cycle 11 P9) with values derived from
the request alone. Options: --stamp S, --banner, --crash-after N (exit without replying to
request N+1), --hang-after N (never reply to request N+1), --reply-stamp S (reply with a
stamp other than the hello's)."""
import hashlib
import json
import sys
from typing import Any, Dict, List


def _h(*parts: Any) -> int:
    text = "|".join(str(p) for p in parts)
    return int.from_bytes(hashlib.sha256(text.encode("utf-8")).digest()[:6], "big")


def play(req: Dict[str, Any]) -> Dict[str, Any]:
    seed = int(req["seed"])
    n = 8 + _h("n", seed) % 9
    actions = [{"t": "a", "i": j, "s": _h("a", seed, j) % 1000} for j in range(n)]
    commits: List[List[int]] = [[], []]
    for j in range(n):
        if j % 3 == 0:
            commits[0].append(j)
        elif j % 3 == 1:
            commits[1].append(j)
    return {"log": {"seed": str(seed), "decks": req["decks"], "actions": actions},
            "result": {"winner": _h("w", seed) % 2, "wins": [1, 0], "rounds": 3,
                       "reason": "stub"},
            "commits": commits}


def label(req: Dict[str, Any]) -> Dict[str, Any]:
    ls = int(req["label_seed"])
    plen = len(req["actions"])
    legal = 2 + _h("l", ls) % 5
    count = min(int(req["k"]), legal)
    n = int(req["determinizations"])
    cands = [{"t": "commit", "card": c, "after": plen} for c in range(count)]
    vals = []
    for c in range(count):
        wins = _h("v", ls, plen, c, req["seat"]) % (n + 1)
        vals.append({"mean": wins / n, "spread": 0.5, "n": n, "wins": wins, "draws": 0,
                     "losses": n - wins, "capped": 0, "rejected": False})
    return {"legal": legal, "candidates": cands, "values": vals, "rollouts": count * n}


def main() -> int:
    argv = sys.argv[1:]

    def opt(name: str, default: str) -> str:
        return argv[argv.index(name) + 1] if name in argv else default

    stamp = opt("--stamp", "r7-stub")
    reply_stamp = opt("--reply-stamp", stamp)
    crash_after = int(opt("--crash-after", "-1"))
    hang_after = int(opt("--hang-after", "-1"))
    if "--banner" in argv:
        print("Godot Engine v4.6.3.stable (stub)\n")
    print(json.dumps({"hello": True, "stamp": stamp, "rules": "r", "format": 1,
                      "godot": "stub"}))
    sys.stdout.flush()
    served = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        req = json.loads(line)
        if req.get("kind") == "quit":
            return 0
        if served == crash_after:
            return 1
        if served == hang_after:
            sys.stdin.read()
            return 0
        served += 1
        body = play(req) if req["kind"] == "play" else label(req)
        reply: Dict[str, Any] = {"id": req["id"], "stamp": reply_stamp}
        reply.update(body)
        reply["us"] = 1000 + served
        print(json.dumps(reply))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
