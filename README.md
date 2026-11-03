# Midnight Earth

A fresh start, 2026-11-02. The previous repository, with its full history, is archived
read-only at [bknize/midnightearth-archive](https://github.com/bknize/midnightearth-archive).

## Layout

| Path | What |
|---|---|
| `docs/` | Obsidian vault: planning notes, specs, ADRs, systems. Hidden from Godot by `docs/.gdignore` |
| `godot/` | Godot 4.6.3 project (Mobile renderer) |
| `scripts/` | `bootstrap.sh`, `check.sh` (the build gate), hooks, `claude-with-env.sh` |
| `.claude/` | Agents, skills and hooks for the spec-driven dev loop |

## Bootstrap

```bash
scripts/bootstrap.sh   # installs gdtoolkit, checks Godot, creates .env from .env.example
make check             # import → lint → parse → boot → test; exit 0 means buildable and testable
```

Godot 4.6.3 is expected at `/Applications/Godot 4.6.app`; set `GODOT_BIN` to override.
Launch Claude Code through `scripts/claude-with-env.sh` so `.mcp.json` sees the tokens in `.env`.

Work is planned in `docs/specs/<slug>/` and tracked in Linear; see `CLAUDE.md` for the rules.
