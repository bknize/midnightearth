# Third-party addons

Vendored as copied source (cycle-0 decision C2). Each entry records the exact upstream
version, where it came from, its license, and every local change. Upgrade by replacing
the folder from the same source and re-applying the patches listed here.

| Folder | Project | Version | Source | License | Local changes |
|---|---|---|---|---|---|
| `card_3d/` | Card3D by Tyson Decker | 3.0.2 (tag `v3.0.2`) | https://github.com/tdecker91/Card3D | MIT (`card_3d/LICENSE`) | `examples/` omitted (bundles third-party card art); `scripts/card_3d.gd` lines 46, 57, 68, 76: `tween.is_running` → `tween.is_running()` (the bare method reference is always truthy, so tweens were never treated as finished) |
| `gdUnit4/` | gdUnit4 by Mike Schulze | 6.2.3 (tag `v6.2.3`) | https://github.com/MikeSchulze/gdUnit4 | MIT (`gdUnit4/LICENSE`) | none |
| `godot_mcp/` | Godot MCP editor plugin (godot-mcp-server) by Tomer Yud | 0.6.1 (tag `v0.6.1`) | https://github.com/tomyud1/godot-mcp | MIT (`godot_mcp/LICENSE`) | none; `cache/` is gitignored |

Upstream Card3D declares Godot 4.7 as its target; it imports cleanly on 4.6.3 as of
2026-11-02 (see cycle-0 plan, Risks).
