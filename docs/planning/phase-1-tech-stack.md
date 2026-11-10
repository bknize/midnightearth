---
type: planning
tags: [planning, phase-1]
status: closed
related: ["[[planning/planning-moc]]"]
created: 2026-11-02
updated: 2026-11-07
uid: 0f3968e1-885c-4732-941f-388209e92578
supersedes:
phase: 1-tech-stack
---

# Phase 1 — Tech stack research and decisions

Research gathered 2026-11-02 for the fresh-start card game. Local facts were checked on
this machine; web facts were gathered by three research agents the same day and should
be re-verified before any purchase. Decisions are recorded at the bottom as Ben makes
them; everything above the Decisions section is evidence.

## What is already on this machine

| Item | State | Note |
|---|---|---|
| Godot | 4.6.3 and 4.5.1 installed (`/Applications/Godot 4.6.app`, `/Applications/Godot.app`) | 4.7 is the current stable upstream; not installed |
| Xcode | 27.1 | iOS export possible today |
| godot-mcp-server | 0.6.1 configured globally in the Claude desktop app (`npx -y godot-mcp-server`) | Archive's editor plugin is 0.5.0 — upgrade needed; 0.6.1 changed `send_input` key handling, so re-test the keyboard limitation |
| score orchestrator | `/Users/Crofts/Dev/Orchestrator`, v0.1.0, MCP `score` | JIRA-only: ~1,000 lines in `src/main/jira/`, zero Linear references, JIRA types leak into ~20 files outside the module. Not running at research time |
| Archive repo | `/Users/Crofts/Dev/nightscience/midnightearth-archive` | Obsidian vault at repo root (dataview, quickadd, templater, smart-connections); `.mcp.json` already registers the Linear MCP (`https://mcp.linear.app/mcp`) |

### Reusable from the archive (all MIT/CC0/OFL unless noted)

| Asset | Path in archive | Fit for a 3D card game |
|---|---|---|
| chun92 Card Framework 1.4.0 + Ben's touch and null-guard patches | `Godot/addons/card_framework/` | 2D Control-based; architecture reference only if we go 3D |
| Balatro foil shader (CC0) | `Godot/shaders/card_foil.gdshader` | canvas_item; would need porting to spatial |
| gdUnit4 v6.2.2 | `Godot/addons/gdUnit4/` | Directly reusable; 6.2.3 shipped 2026-11-01 |
| Godot Touch Input Manager 2.1.2 | `Godot/addons/godot_touch_input_manager/` | Reusable for mobile gestures |
| night_ui addon + midnight_earth skin | `Godot/addons/night_ui/` | Portable by design; gate G4 (Ben's click-through) never passed |
| vault-interrogator and obsidian-autolink skills | `.claude/skills/` | Spec Kit flow (interrogate → spec → plan → tasks); Phase 2 input |
| Fonts (Cinzel Decorative, Exo 2, Metamorphous, Lancelot, Caudex) | `Godot/ui/fonts/` | OFL; reusable if the art direction survives |

## 3D card rendering in Godot 4

**Finding: exactly one maintained 3D card framework exists for Godot 4.** Everything
else is stale or 2D.

| Name | 2D/3D | Godot | License | Maintained | What we would reuse | Risk |
|---|---|---|---|---|---|---|
| [tdecker91/Card3D](https://github.com/tdecker91/Card3D) | 3D meshes | 4.5–4.7 (v3.0.2, 2026-10-13) | MIT | Yes | `Card3D` hover/move tweens, fan/line/pile layouts, `DragController`, collection model | Solo project; mouse-only input; no flip tween, no foil, no zones/rules; one `is_running` bug |
| [Godot Card FX](https://binbun3d.itch.io/godot-card-fx) (Binbun) | 3D spatial shader | 4.x (2026-03) | CC0, pay-what-you-want | Yes | 5-layer parallax holo/foil, 24 presets | No mobile notes; itch download not git |
| [thebasdagger foil](https://godotshaders.com/shader/simple-dynamic-holographic-card-effect-foil/) | 3D spatial shader | 3.x syntax | CC0 | No (2021) | Simplest NORMAL-driven foil; trivial port | Minimal look |
| [chun92/card-framework](https://github.com/chun92/card-framework) | 2D | 4.6+ | MIT | Yes (2026-05) | Hand/pile/drop-validation design | 2D only |
| [Simple Cards v2](https://github.com/twdoor/simple-cards-v-2) | Control + SubViewport | 4.5+ | MIT | Yes (2026-10) | Layout editor, slot/drop-zone design | Not meshes |
| [foilsmith](https://github.com/Tryptophan/foilsmith) | canvas_item | 4.4+ | MIT | Day-old | Finish-map asset pipeline idea | Too new; heavy for mobile |
| [db0 CGF](https://github.com/db0/godot-card-game-framework) | 2D | 3.x only | AGPL | Dormant | Architecture reference only | Godot 3, AGPL |

Hand-fan math worth copying: Card3D's `fan_card_layout.gd` (arc divided by n+1, rotate
about Z), or the Curve-based Inscryption-style approach from the
[forum thread](https://forum.godotengine.org/t/godot-4-3d-cards-fanning/90629).

**Realistic 3D plan:** adopt Card3D (or copy its ~5 scripts) as scaffolding, take foil
from Card FX or a ported spatial shader, and build ourselves: flip/draw/play animations,
play-region zones, touch input, rules.

## Mobile and desktop rendering

- Godot docs: **Mobile renderer** is the default on mobile; Forward+ is poorly optimized
  there. Mobile on iOS = Metal 3, iOS 16+, A12+. Compatibility (GLES3) is the fallback
  and the **only renderer the iOS Simulator supports**; on Apple-silicon Macs the iOS
  build can run natively instead.
- Card foil shaders are plain raster fragment shaders; no structural mobile problem.
  Keep shaders Compatibility-clean (mediump-safe math, no SCREEN_TEXTURE) so Simulator
  testing and fallback stay possible.
- Known iOS Metal issues to watch: script-created `ShaderMaterial` + shader baker
  (godot #124088; assign materials in the inspector or disable the baker), slow
  first-launch pipeline compilation (#103006; warm materials at boot).
- iOS export: from macOS with Xcode, Team ID + bundle ID, provisioning via
  `GODOT_IOS_PROVISIONING_PROFILE_UUID_*` env vars.

## Godot MCP and AI helpers

| Tool | Purpose | Maintained | Recommend |
|---|---|---|---|
| [godot-mcp-server 0.6.1](https://github.com/tomyud1/godot-mcp) (tomyud1, MIT) | Editor-attached: run_scene, screenshot, input, runtime queries, batch edits, undo | Yes (2026-10-17) | **Keep**; upgrade plugin to 0.6.1 |
| [Erodenn/godot-mcp-runtime](https://github.com/Erodenn/godot-mcp-runtime) (MIT) | Launches the Godot binary itself, no editor; off-screen "background mode" screenshots, key/text input, UI clicks by node name | Yes (2026-10-30) | **Trial** for editor-free verification |
| [GodotLens-MCP](https://github.com/pzalutski-pixel/godotlens-mcp) (Apache-2.0) | Godot LSP diagnostics + runtime tools; 4.6 floor | Yes (2026-10-17) | Trial if LSP gates wanted |
| GDAI MCP ($19) / Godot MCP Pro ($15) | Alternative editor MCPs | Yes | No; redundant |
| Coding-Solo / ee0pdt / bradypp godot-mcp | CLI or file-level MCPs | Stale | No |

No official Godot AI/MCP effort exists; the Godot Foundation restricts AI-written
engine contributions (2026-06-30), which does not affect game projects.

## Headless testing and compile gates

| Tool | Finding |
|---|---|
| [gdUnit4 6.2.3](https://github.com/MikeSchulze/gdUnit4) | Best maintained for 4.6 (released 2026-11-01). CLI via `GdUnitCmdTool.gd`; JUnit `results.xml`; exit 0 pass, 100 failures, 101 warnings, 103 headless refused unless `--ignoreHeadlessMode`. GitHub Action `MikeSchulze/gdunit4-action@v1` |
| GUT 9.6.1 | Fine, but 4.6 is now a maintenance branch; known to exit 0 when a test script fails to load |
| gdtoolkit 4.5.0 (gdlint/gdformat) | Covers 4.5/4.6 syntax; slow release cadence (2025-10) |
| `godot --headless` exit codes | **Not trustworthy.** `--import`, `--editor --quit` and scene runs exit 0 on parse errors ([forum audit](https://forum.godotengine.org/t/things-that-exit-0-in-godot-4-headless-even-though-they-failed-measured-reproducible/145990)). Gate by grepping `SCRIPT ERROR|Parse Error|ERROR:` and requiring an expected boot line |
| Headless screenshots | `--headless` renders nothing; `--write-movie` aborts. macOS recipe without the editor: `override.cfg` positioning the window off-screen + `open -g -j` + an autoload that saves the viewport, or `--write-movie --fixed-fps 24 --quit-after N` |
| CI | `chickensoft-games/setup-godot@v2` or `barichello/godot-ci:4.6.3` |

**Proposed agent test loop.** Workers prove a change builds with one `make check`:
`godot --headless --import --path . --quit`, `gdlint` on changed files, a 2-second
boot run grepped for errors and for a "Main ready" line, then gdUnit4 with JUnit output
(exit 0 or 101 = pass). Wire gdlint plus a single-file parse gate as a PostToolUse hook.
The orchestrator verifies visually through godot-mcp-server with the editor open
(run_scene, mouse/action input, screenshot, runtime log), driving keyboard and popup
paths programmatically per the known input limits.

## Art generation services (agentic, billed to the service)

Prices are per image at ~1024px unless noted; from official pages where fetchable,
otherwise from dated aggregators. Verify before committing.

| Service | API | MCP | $/img std | $/img hq | Style consistency | Transparent | Commercial | Verdict |
|---|---|---|---|---|---|---|---|---|
| [Replicate](https://replicate.com/docs/reference/mcp) | token | official (`mcp.replicate.com`, `npx replicate-mcp`) | $0.003–0.025 | $0.04–0.07 | FLUX LoRA under $2, seeds | via RMBG model | yes, on-platform | **Recommend** |
| [fal.ai](https://fal.ai/pricing) | key | docs-only official; community | $0.003–0.012/MP | $0.045–0.048 | LoRA ~$2, seeds, multi-ref | RMBG $0.018 | yes, verify per model | **Recommend** (interchangeable twin) |
| [Recraft](https://www.recraft.ai/docs/api-reference/pricing) | key (units) | official remote, but bills subscription credits not API units | $0.035 | $0.21 | `style_id` from 1–10 refs | yes $0.01, native SVG | yes, full ownership | **Recommend** for icons/UI/vector via HTTP API |
| Google Nano Banana 2.1 | key | community | $0.034 | $0.134 (Pro) | up to 14 ref images, no LoRA | no | yes, SynthID watermark | Viable for edit-heavy fixes |
| OpenAI gpt-image-2 / 2.5 | key | community | $0.006–0.053 | $0.21 | ref images only | yes | yes + indemnity | Viable; hq expensive |
| Black Forest Labs direct | key | none | $0.015–0.045 | $0.048–0.07 | multi-ref; hosted finetune gone | no | yes | Only for day-0 models |
| Ideogram 4.5 | key | community | $0.03–0.06 | $0.10 | style refs, $40 custom model | no | yes | Text/titles niche |
| Stability | key | community | $0.03 | $0.08 | Style Guide/Transfer | $0.05 | under $1M revenue | Skip |
| Scenario | key (Starter+) | none | $15–45/mo sub | — | best style lock (private models) | yes | yes | Later, if style lock is the bottleneck |
| Leonardo | key | community | opaque | opaque | Elements/training | yes | paid plans | Skip |
| Layer.ai | PAT | official (OAuth) | ~$0.06–0.13 | — | style training | model-dependent | yes | Skip, markup |
| Midjourney | none | none | — | — | — | — | — | Skip |

**Budget math** at ~$0.03 per image × 4 variants = $0.12 per accepted card: $30/month ≈
230 accepted cards, $50 ≈ 400. At the HQ tier (~$0.048 × 4): $30 ≈ 150, $50 ≈ 260. The
MVP's 20–40 cards cost under $10. 200 UI icons through Recraft ≈ $7.

## Backend

The MVP is 1v1 against a bot, fully local. No server, Docker or AWS is required until
online human-vs-human is in scope. The archive's AWS/Django/Redis stack was retired by
ADR 0010 and is reference only.

## Cost table for the Phase 1 decisions

Effort is a rough size for one dev cycle of the planned orchestrator flow.

| Decision | Option | Effort | What makes it expensive |
|---|---|---|---|
| Card rendering | 3D: Card3D scaffolding + Card FX foil, build flip/zones/touch ourselves | M | Touch input and zones from scratch; two shader sources to reconcile |
| | 3D from scratch, copying Card3D's math | M+ | Same, plus rewriting what Card3D already gives |
| | 2D: chun92 framework + Balatro foil (already patched for touch) | S | Contradicts the "Godot 3D" brief; limits depth effects |
| Renderer + version | Godot 4.6.3, Mobile renderer, Compatibility-clean shaders | S | Shader discipline; Simulator only runs Compatibility |
| | Godot 4.7.x | S | One more install; gdUnit4 v7 line; Card3D's declared target |
| Art pipeline | Replicate (official MCP + token) + Recraft HTTP for icons; FLUX LoRA for style | S | LoRA needs 15–30 approved reference cards first |
| | fal.ai primary | S | Community MCP only; otherwise equivalent |
| | Scenario subscription | S | $45/mo for training tier; credits expire |
| | Placeholder art for MVP, decide later | XS | Art direction drifts without early samples |
| Test loop | `make check` gate for workers + godot-mcp-server for orchestrator | S | Exit codes untrustworthy; grep-based gating |
| | Add Erodenn runtime MCP for editor-free screenshots | S | Trial cost; new project |
| UI addon | Lift night_ui as-is | S | Unpassed G4 gate; square-corner skin assumptions |
| | Plain Godot Theme, fresh | S | Rebuilds what night_ui has |
| Backend | None for MVP | XS | Engine must stay deterministic/serializable if online PvP comes later |

## Decisions

### Round 1 (Ben, 2026-11-02, all recommendations accepted)

| # | Decision | Consequence |
|---|---|---|
| D1 | **3D cards on Card3D scaffolding.** Adopt tdecker91/Card3D (MIT) for layouts, tweens and drag-drop; foil from Godot Card FX (CC0) or a ported spatial shader; flip/draw/play animations, play-region zones, touch input and rules are built in-house. | Vendor Card3D under `addons/` with a THIRD_PARTY_LICENSES entry; fix its `is_running` bug on import; chun92 framework is reference only |
| D2 | **Godot 4.6.3, Mobile renderer, Compatibility-clean shaders.** Stay on the installed 4.6.3; move to 4.7 later as a point upgrade. | Project features `4.6`, `Mobile`; shader rule: mediump-safe math, no SCREEN_TEXTURE, test under Compatibility in the iOS Simulator; gdUnit4 stays on the 6.2.x line |
| D3 | **Art via Replicate + Recraft, $30/month target.** Replicate's official MCP with an API token is the primary image service; a FLUX LoRA is trained once 15–30 reference cards are approved; Recraft's HTTP API handles icons, UI and vector. | Tokens live in `.env` (gitignored), never in `.mcp.json`; Phase 2 wires the MCP; no Claude spend on art |
| D4 | **No backend for the MVP; engine stays deterministic and action-serializable.** Bot opponents only. Online PvP is not planned but must not require a rewrite. | Match engine is pure GDScript with seeded RNG and a replayable action log; no network-dependent scene; no Docker/AWS provisioning |

Amended for PVP by ADR 0005 ([[decisions/0005-match-server-for-pvp]], 2026-11-07): PVE stays local; PVP is served by a headless process on the testing PC.

### Round 2 (Ben, 2026-11-02; 3c chosen explicitly, 1a/2a/4a accepted by default)

| # | Decision | Consequence |
|---|---|---|
| D5 | **Worker build gate is one `make check` plus a PostToolUse hook.** `make check` = headless import, gdlint on changed files, a 2-second boot run grepped for `SCRIPT ERROR\|Parse Error\|ERROR:` and for a "Main ready" line, then gdUnit4 with JUnit output (exit 0 or 101 pass). The hook runs gdlint and a single-file parse gate on every edited `.gd`. | Workers never trust Godot exit codes; the gate script is the first artifact of cycle 1 |
| D6 | **Orchestrator verifies through godot-mcp-server 0.6.1 with the editor open**, after upgrading the editor plugin from 0.5.0 and re-testing keyboard input. Erodenn's runtime MCP gets a one-cycle trial for editor-free screenshots. | Keyboard and popup paths are driven programmatically until the re-test says otherwise |
| D7 | **night_ui stays in the archive.** UI is built fresh with plain Godot Theme resources. | No addon lift, no theme contract carried over; keep "theme-driven, no hardcoded visuals" as a plain style rule only if a later UI cycle wants it |
| D8 | **Build cadence: desktop every cycle, iOS at milestones.** Each cycle runs `make check` and a macOS run through the MCP; the first iOS device/simulator build lands once a full match against a bot is playable; a Windows export preset exists but is untested until a milestone; Android is not planned. | Export presets are created in cycle 1 but only macOS is exercised per cycle |

Phase 1 is closed. Open items carried to Phase 2: wiring the Replicate MCP and
token, the Linear-versus-JIRA question for score, and where planning docs live
once the Obsidian vault layout is decided.
