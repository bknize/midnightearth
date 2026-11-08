---
name: art
description: >
  Make Midnight Earth's art through the Fable artist agent and the Replicate MCP: set the
  art direction with Ben, run a cheap exploration pass, generate card art in capped
  batches, and approve picks into godot/art/ with a reproducible manifest. Use for
  "/art direction", "/art explore", "/art generate c01-c05", "/art approve", "make card
  art", "try some styles", or anything that spends Replicate credits.
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent, SendMessage, SendUserFile]
license: MIT
---

# /art: art through the artist agent

Decision D3 puts art on Replicate (billed there, $30/month target, never Claude spend)
with a FLUX LoRA trained once 15–30 reference cards are approved. ADR 0003
(`docs/decisions/0003-art-agent.md`) sets up how: a Fable `artist` subagent does the
creative work, the orchestrator relays and approves, and approved images are committed
through Git LFS with a manifest that can regenerate each one.

## The pipeline

1. `/art direction` — the artist interviews Ben and writes `docs/art/art-direction.md`.
2. `/art explore` — a cheap pass (FLUX schnell class, about 50 images) across the
   directions that note leaves open, so Ben picks a look from pictures, not words.
3. `/art generate <ids>` — capped batches of real assets (card art first: the 15–30
   reference cards the LoRA needs, then the 20 MVP cards of R6).
4. `/art approve` — Ben's picks go into `godot/art/` and `art/manifest.json`.
5. LoRA training is its own step, proposed by the artist in a `ROUND` with its cost,
   once enough references are approved. It needs a new tool grant in `artist.md`.

## Who does what

- **The orchestrator** (the session Ben ran `/art` in): checks the token, cuts the
  branch when a step will commit, writes the brief, relays, runs `scripts/art-approve.sh`,
  commits when Ben says so. It never writes prompts or picks for Ben.
- **The artist** (`.claude/agents/artist.md`, Fable): interviews, writes prompts and
  `docs/art/` notes, generates within the cap, builds contact sheets, recommends.

## Step 0 (orchestrator, every verb)

1. Check the Replicate MCP answers: call `mcp__replicate__get_account`. A 401, or no
   `replicate` tools at all, means `REPLICATE_API_TOKEN` is missing from the main
   checkout's `.env` (`scripts/replicate-mcp.sh` reads it there) or the session started
   before it was set; tell Ben and stop. Never ask for the token in chat.
2. Branch (`CLAUDE.md`, Git). `direction` writes a note: cut `docs-art-direction` from
   `master` (`git switch -c` in the main checkout when nothing else shares it, else
   `git branch` plus a worktree, and dispatch the artist there). `explore` and
   `generate` write only gitignored candidates and need no branch. `approve` commits
   images: cut `art-<batch>` from `master`, or approve onto the cycle branch when the
   art belongs to a running cycle.
3. Read `art/ledger.jsonl` (if present) for this month's estimated spend, and include
   it in the brief.

## The brief

Dispatch with `Agent`, `subagent_type` `artist`, no worktree isolation (it writes
gitignored candidates in the checkout it runs in). The prompt carries:

- the verb, and Ben's request in his own words;
- for `explore` and `generate`: the batch name (kebab-case, for example
  `explore-01` or `cards-c01-c05`), the model, the image cap, and the month spend so
  far. Defaults: `explore` uses `black-forest-labs/flux-schnell` with a 50-image cap;
  `generate` uses the model the direction note names with 4 variants per asset;
- for `generate`: the asset ids and what each one is (from `godot/engine/data/cards.json`
  and any lore note Ben points to);
- anything this conversation already settled, with who settled it.

## The relay

The artist is a subagent and cannot reach Ben, so the orchestrator relays:

1. The artist ends every message with `ROUND n`, `REVIEW` or `DONE` (its agent file).
2. Show Ben a `ROUND` or `REVIEW` block word for word, plain text, no widget, adding at
   most one line of your own. For a `REVIEW`, also send each contact sheet it names with
   `SendUserFile` (`display: render`) so Ben sees the images.
3. Send Ben's reply back unchanged with `SendMessage`, prefixed `Ben:`; your own
   questions go prefixed `Orchestrator:`. Never send a reply Ben did not give.
4. On `DONE`, check what it claims: the note's frontmatter, the batch folders, the
   ledger lines. Then report to Ben in a few lines.

## /art direction

The artist interviews in rounds and stops when answers stop changing the prompts. It
covers at minimum: mood and genre; palette (the archived "ethereal arcana" palette and
the style tile at `../midnightearth-archive/design/assets/style-tile.png` are one option,
never the default); rendering style; framing (full-bleed or a window inside a frame) and
the calm zones the cost, power and name need on a 5:7 card; subject matter (whether
the archive's Characters, Factions and Locations lore is in play, and what the 20 cards
depict); references Ben supplies; and the no-gos. It then writes
`docs/art/art-direction.md` (type `reference`, status `seedling`) with the decisions, a
prompt skeleton (subject slot + fixed style block) and the model choice for `generate`,
plus the open questions `explore` should answer. Add the note to `docs/home.md` or the
relevant MOC so it is not an orphan. Commit on Ben's word.

## /art explore and /art generate

The artist generates within the cap, downloads every output with
`scripts/art-fetch.sh`, builds sheets with `scripts/art-sheet.py`, and sends a
`REVIEW`. Ben's answers can start another batch inside the same cap; past the cap the
artist asks in a `ROUND` with the extra cost. `explore` ends with the artist updating
the direction note with what Ben picked (that note's branch, committed on his word).

## /art approve

For each pick Ben names (orchestrator, on the branch from step 0):

```bash
scripts/art-approve.sh art/candidates/<batch>/<name>-<n>.png <asset-id>          # card art
scripts/art-approve.sh <image> <asset-id> --kind ref --replace                   # LoRA reference
```

It copies the image to `godot/art/<kind>/<asset-id>.png` (PNG, converted with `sips`
if needed) and writes the sidecar's model, version, input, seed and prediction id into
`art/manifest.json` under `<kind>/<asset-id>`. It refuses to overwrite without
`--replace`. Then `git add godot/art art/manifest.json` and commit when Ben says so;
`git lfs ls-files` must list the new images before the commit. Wiring the images into
the card face is cycle work, not part of `/art`.

## Files

| Path | Tracked | What |
|---|---|---|
| `art/candidates/<batch>/` | no (gitignored) | Downloaded outputs, sidecars, `sheet.png` |
| `art/ledger.jsonl` | no (gitignored) | One line per prediction: date, model, images, estimated USD |
| `art/manifest.json` | yes | Every approved asset and how to regenerate it |
| `godot/art/<kind>/<id>.png` | yes, Git LFS | Approved images (`.gitattributes`) |
| `docs/art/` | yes | Art direction and batch notes (vault) |

The ledger is an estimate from published prices; Replicate's billing page is the truth.
Replicate stopped offering spend limits to new customers on 2025-07-01, so there is no hard stop: check the billing page after each batch. `ART_MONTHLY_BUDGET_USD` (default 30) is the
soft stop `art-fetch.sh` enforces.
