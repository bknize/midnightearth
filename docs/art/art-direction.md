---
type: reference
tags: [art, reference, cards]
status: seedling
related: ["[[decisions/0003-art-agent]]", "[[planning/phase-1-tech-stack]]", "[[home]]"]
created: 2026-11-03
updated: 2026-11-04
uid: 5bf8298d-cd5f-4d0b-8566-50f3839f1ed3
supersedes:
---

# Art direction

> What every Midnight Earth card illustration looks like, decided with Ben on 2026-11-03
> in the `/art direction` interview and confirmed from pictures in `/art explore`
> (`explore-01`, 2026-11-04), with the prompt skeleton and model every `/art generate`
> batch starts from.

## Decisions

### `/art direction`, 2026-11-03

Four rounds, relayed by the orchestrator. Round 3 was asked twice (the first version
before the Pinterest board could be read, the second after); Ben's answers below are the
ones he confirmed after the orchestrator pointed out the mix-up.

| # | Question | Ben's answer |
|---|---|---|
| 1.1 | Mood and genre | (a) Gothic sci-fi noir, as the archive's world notes: permanent night, vampire Houses, grounded near-future tech next to blood magic |
| 1.2 | Lore in play | (a) Yes, by name: the 20 MVP cards depict the archive's characters, factions and locations |
| 1.3 | References | (b) A Pinterest board, `https://www.pinterest.com/bk0542/midnight-earth/` |
| 2.1 | Palette | (a) Cold night with one warm accent: obsidian, deep plum and steel-blue shadows, garnet accent, thin ivory moonlight; one palette for the whole deck |
| 2.2 | Rendering | **(c)** Graphic / stylised (not painterly, not photoreal) |
| 2.3 | Framing | (a) Full-bleed art behind the frame, with calm zones for name, cost and power |
| 2.4 | Composition | (b) A central figure on every card, including faction and location cards |
| 3.1 | Stylised flavour | **Ink and flat tone**: confident black ink line, two or three flat values, garnet as the single spot colour, paper or screen-print texture |
| 3.2 | Background | **Atmospheric place** behind the figure (Nocturne's skyline, the Iron Grave, haze, a distant light), not a flat field. *Narrowed by explore 2 below: the place is one motif on a flat field.* |
| 3.3 | Model for `generate` | (a) `black-forest-labs/flux-dev`, $0.025 an image |
| 3.4 | No-gos | (a) The usual card-game set (below) |
| 4.1 | The 20 subjects | (a) 13 characters, 3 factions, 4 locations (list below) |
| 4.2 | Faces | (a) Mostly hidden (masks, veils, hoods, helmets); bare faces only for the leads. *Widened by explore 5 below.* |
| 4.3 | Shot | (a) Full-length, feet visible, figure about 60% of the card height, centred |

### `/art explore`, `explore-01`, 2026-11-04

53 images: 45 on `flux-schnell` across five sheets (one per open question group), the
8-image `flux-dev` guidance pair Ben approved in round 1, and a 4-image confirmation of
the reordered skeleton. Ben picked from the sheets and answered two rounds; where a
picked image and a lettered answer disagreed, round 2 settled it.

| # | Question | Picked image | Ben's answer |
|---|---|---|---|
| E1 | Line weight and value count | `a3-heavy-3v` | **Heavy woodcut line, three flat values plus ivory** (round 2, 1a) |
| E2 | Background density and aspect | `b4-few-2x3` | **Bare field at 2:3**: the darkest flat value with one motif at most (round 2, 2b) |
| E3 | Garnet | `c3-garnet-lining` | **Costume lining or interior**: the inside of a hood, a collar, a sash (3a) |
| E4 | Grain | `d3-grain-none` | **None in the prompt**; paper grain, if wanted, is a Godot overlay later so it is uniform across the deck (4a) |
| E5 | Faces | `e2-face-bare` | **Every named character bare-faced and in shadow**; a face is hidden only where the costume is a mask or helmet; faction and location figures hidden (round 2, 3a) |
| E6 | Guidance on `flux-dev` | `f2-dev-guidance-2.5` | **2.5** (6b) |
| E7 | The sigil that renders as a cross | | **Crosses are fine** on Vesperi House and cathedral-ship cards (7b) |
| E8 | The last five images under the cap | `g1-confirm-skeleton` | One confirmation run of the reordered skeleton (8a) |

What the sheets found, beyond the picks:

- `flux-dev`'s logs report that CLIP truncates the prompt at 77 tokens, which is about
  the length of a subject slot; the style block after it reaches only the T5 encoder.
  That is why the `flux-dev` sheet drifted painterly while `flux-schnell` held the ink
  look. The skeleton below therefore opens with the style words.
- "coarse paper", "print" and "risograph" in the prompt pull in white deckle borders and
  fake artist signatures and captions (every image on the grain sheet, several
  elsewhere). Those words are gone from the skeleton and "no border, no signature, no
  caption" is in it; the confirmation run still produced a border on two of four, so
  the avoid list keeps it and `generate` should expect to discard some variants for it.
- "a small garnet sigil" renders as a Christian cross almost every time (E7 accepts
  this for the Vesperi and cathedral-ship cards; elsewhere, describe the shape or drop
  the sigil).
- Figures come out 80-90% of the frame height, not 60%, with the window arch or the
  moon in the top band. "centred in the lower two thirds of the frame, the top quarter
  of the frame an empty flat dark wall" fixed this on two of four in the confirmation.
- An unspecified mask becomes a skull; say what the mask is.
- "veil" is ignored by `flux-schnell` two times in three; "deep hood, face in full
  shadow" or a named mask is respected.
- `flux-schnell` and `flux-dev` both draw coherent, consistent bare faces for this
  look, which is what let E5 widen the bare-face rule.

The archive's "ethereal arcana" style tile
(`../midnightearth-archive/design/assets/style-tile.png`) was offered as one option and
not chosen. What carries over from it: deep plum `#2A1136`, obsidian `#0D0B12` and garnet
`#78121E`. What does not: lilac, blush and spectral cyan, the soft cosmic glow, crystal
and halos.

## The look

**World.** An alternate Earth held in permanent night, ruled by dynastic vampire Houses.
Near-future technology sits beside blood rites nobody calls magic. The frontier is the
rest of Sol: hollowed asteroids, cathedral-ships, a dead iron orb that fell on the city.
Every card shows one person (or one being) standing in a place from that world.

**Palette.** Cold night with one warm accent. Shadows are obsidian `#0D0B12` and deep
plum `#2A1136`; the mid value is a steel blue-grey; the light is a thin bone-ivory
`#F7F4EC` from a moon, a window or a lamp. Garnet `#78121E` is the single spot colour and
is rationed: by E3 it lives in the costume, as the inside of a hood, a collar, a sash or a
lining, where the eye finds it without leaving the figure. A small flat red lamp is the
fallback where a costume has no interior to show; never a red glow or gradient. Never
more than one garnet idea per card. No other saturated hue.

**Rendering.** Ink and flat tone, heavy woodcut line (E1). A thick black ink contour
with carved solid shadow shapes does the drawing; the colour is exactly three flat values
(obsidian dark, plum or steel-blue mid, bone-ivory light) with no gradients, no airbrush,
no painterly brushwork, no photographic detail. No texture is asked for in the prompt
(E4): the sheets showed paper and halftone words buy artefacts and are indistinguishable
at card size; if the deck wants grain, a Godot overlay adds it uniformly later. The feel
is a woodcut poster, not a digital painting. This look was the most consistent across
the explore sheets and reads clean at 2.5 x 3.5 units.

**Figure.** Full-length, feet visible, centred, still, facing the viewer or in
three-quarter view, standing in the lower two thirds of the frame so the top quarter
stays empty. Posed like the board: composed, ceremonial, weight on both feet, hands
visible and doing something small (holding a relic, resting on a blade, pressed
together). Costume is dark, layered, ceremonial or cult-like: robes, hoods, veils,
chains, headdresses, work gear with ritual trim. Faces (E5): every named character shows
a bare face, pale and held half in solid shadow; a face is hidden only where the costume
is itself a mask or helmet (the Barrow warden's welded mask, Tamsin Reyes's respirator,
Silas Drummond's breathing mask, Vale Okafor's eye band, Geppetto's glass head, Ferrox's
shell). Faction and location figures keep their faces hidden by a deep hood or a named
mask. Describe the mask; never leave it to the model.

**Background.** A bare field (E2): the darkest flat value fills the frame, and at most
one motif from the place stands in it, drawn in the mid value or lit in ivory: one tall
window, one crescent moon, one sealed gate, one strip light, one spire silhouette. No
skyline, no second light, no texture on the wall. The figure's silhouette reads first
because there is nothing to compete with it; the motif names the place.

**Framing and calm zones.** The art is full-bleed behind the card frame. The frame
carries the name, cost and power, so every prompt keeps three zones uncluttered: the
top band (about the top 12% of the image) for the name, and the bottom-left and
bottom-right corners (about 18% x 12% each) for cost and power. In practice: the figure
sits in the lower two thirds, the top quarter is empty dark field, the one motif sits
beside or behind the figure's torso (not above the head), and the bottom corners hold
only floor. Art is generated at `2:3` (E2); the 5:7 face crops about 3.5% off the top and
bottom, so nothing important sits within 5% of the top or bottom edge either.

**Recurring motifs** (from the board, use sparingly, one per card): a crescent moon or an
eclipse beside the figure; one piece of monumental grey architecture; a single figure in
a wide empty place.

## No-gos

From the artist's brief: no text, letters or numbers in the image; no living artists,
real brands, logos or copyrighted characters in prompts. Added by Ben (3.4 a): no gore
beyond implied blood; no sexualised figures; no modern firearms as the focal object; no
real-looking faces of real people. From the look itself: no gradients or soft painterly
rendering, no lilac, cyan or blush, no second saturated hue beside garnet, no busy top
band or bottom corners. From `explore-01`: no paper, print or risograph words in the
prompt (they bring borders and signatures); no unspecified masks (they become skulls);
no red glow as the garnet idea.

## Prompt skeleton

Every prompt is the style opener, then the subject slot, then the fixed closing block,
in this order. The opener comes first because CLIP reads only the first 77 tokens
(`explore-01` finding); the opener and closing block are the same strings for every
card so the LoRA later learns one look.

**Style opener** (verbatim, first):

```
Ink and flat tone illustration, heavy woodcut black ink line, carved solid shadow
shapes, exactly three flat colour values plus bone-ivory, no gradients, no painterly
brushwork.
```

**Subject slot** (one or two sentences, per card):

```
<who>, <what they wear and hold>, <the garnet: the inside of a hood / a collar / a sash>,
<bare face pale and half in solid shadow | face hidden by <named mask>>, standing very
straight, <hands doing what>, full-length, feet visible, centred in the lower two thirds
of the frame, the top quarter of the frame an empty flat dark <wall | sky>. Background a
bare flat dark <wall | sky> with <one motif> <where>, nothing else.
```

**Fixed closing block** (verbatim, last):

```
Palette: obsidian black, deep plum, steel blue-grey, thin bone-ivory, one garnet red
accent only. Gothic science-fiction noir, permanent night. Portrait card illustration,
no text, no letters, no logos, no border, no signature, no caption.
```

The confirmation prompt that proved this order (`g1-confirm-skeleton`, seed 1101) is
the reference instance: Thessaly Vesperi in a deep hood lined garnet, bare face half in
shadow, a bare wall and one tall window.

**Avoid list** (FLUX has no negative prompt; add as "no ..." at the end only when a
batch shows the problem): photorealistic, 3D render, soft gradients, lens blur, lilac,
cyan, pink, multiple light sources, cropped feet, text, border, signature, caption,
skyline, skull mask.

**Parameters** (`black-forest-labs/flux-dev`, an official model, through
`create_models_predictions` with `Prefer: wait`; the Replicate MCP's `get_models`
returned no schema body on 2026-11-04, so the inputs below are from the published
schema and were accepted by the API):

| Input | Value | Why |
|---|---|---|
| `aspect_ratio` | `2:3` | Ben's pick (E2). flux-dev takes no width/height; 2:3 (0.667) and 3:4 (0.75) bracket 5:7 (0.714); at 2:3 the frame crops about 3.5% off top and bottom. Record this in each sidecar. |
| `megapixels` | `1` | About 832 x 1216 at 2:3 |
| `num_outputs` | `4` | Four variants per asset in one prediction (the `generate` default) |
| `num_inference_steps` | `28` | Model default |
| `guidance` | `2.5` | Ben's pick (E6) from the same-seed pair; softer than 3.5, not looser |
| `output_format` | `png` | Lossless for approval |
| `seed` | chosen per prediction and recorded | Approved images must be reproducible |
| `go_fast` | `false` | Full-precision run for assets |

`explore` used the same prompts and ratios on `black-forest-labs/flux-schnell`
(`num_inference_steps` 4, `go_fast` true, no `guidance` input exists) with
`num_outputs` 2 to 4.

## The 20 cards

Ben chose the subjects (4.1 a). The card ids in `godot/engine/data/cards.json` are
placeholders with a cost and power each; the mapping below pairs the weightiest subjects
with the highest costs and is a **proposal for `/art generate`** to confirm, not a
decision. Subject slots are drafts for the artist to tune per batch; at `generate` each
one is rewritten into the skeleton above, which means: the place reduces to its one
motif (E2), the garnet moves into the costume (E3), and every named character gets a
bare face in shadow unless the slot names a mask (E5).

| Id | Cost/Power | Subject | Type | Subject slot (draft) |
|---|---|---|---|---|
| c20 | 7/9 | Ferrox | character | an ancient being, more silhouette than body, in a shell of pitted iron and bone, no face at all, standing at the centre of a crater in a dark city, embers below, a dull red glow from inside the shell |
| c19 | 7/7 | Livia Vesperi | character | the matriarch of a vampire House, tall, in a high-collared black robe with a thin garnet lining, bare face in shadow, hands folded over a relic, in the nave of a cathedral-ship, tall dark windows, cold light from above |
| c18 | 6/8 | The Iron Grave | location | a lone figure in a sealed suit and hood, small, standing on a ridge before a vast pitted iron sphere half-buried in a city, haze, one faint red light on the sphere |
| c17 | 6/6 | Geppetto | character | a human-shaped machine with a translucent glass body and visible circuitry, no face, in a long coat, one hand raised with fine threads running from the fingers, on the bridge of an outlaw ship, instruments dark, a single lamp |
| c16 | 5/7 | The Compline | location | an acolyte in a veiled headdress and layered black vestments at the altar of a cathedral-ship, hands raised over a basin, pillars and a tall window behind, a garnet glow in the basin |
| c15 | 5/5 | Perpetua Vane | character | a woman in grey wrappings and a long coat, bare face in shadow, the suggestion of two cut scars on her back under the coat, standing in a tunnel of the undercity, warding chalk marks on the wall, a lantern on the floor |
| c14 | 4/6 | Mara Voss | character | a lean human fighter in patched frontier gear and a scarf, bare face hard and in shadow, a short blade in hand, standing in an asteroid tunnel, pipes and cables, a work light behind her |
| c13 | 4/5 | Imogen Hask | character | a human ship captain in a worn salvage jacket and cap, bare face in shadow, a hand on a bulkhead door, in the cramped corridor of a small ship, a porthole showing the belt rock, one overhead light |
| c12 | 4/4 | Nocturne | location | a hooded watcher in House livery standing on a spire balcony above an endless night city, lit windows far below, haze, a crescent moon behind the head |
| c11 | 3/5 | Silas Drummond | character | a gaunt man in a long coat and goggles pushed up, face hidden by a breathing mask, surrounded by hanging maps and wires in a buried stronghold, one desk lamp |
| c10 | 3/4 | Corvin Vesperi | character | the young heir of a vampire House in a fitted dark uniform with a loosened collar, bare face turned away in shadow, one hand holding a small hidden device, in a quiet gallery of the cathedral-ship, a cold window |
| c09 | 3/3 | Thessaly Vesperi | character | a young woman in formal House vestments with a deep hood lined garnet, bare face half in shadow, standing very straight, hands clasped, a bare chapel wall and one tall window (the `explore-01` reference instance) |
| c08 | 2/4 | Thane Ostrow | character | a vampire in a long salvage coat and a half-mask, standing at a cargo rail of a small ship, crates and chains, a shaded lamp |
| c07 | 2/3 | The Barrow | location | a warden in a heavy hooded coat and welded mask standing before a sealed gate deep in the undercity, chalk wards on the stone, a lantern hung on the gate |
| c06 | 2/3 | Vale Okafor | character | a psychic operator in a headset with cables, eyes covered by a dark band, seated upright in a cramped comms bay with hands on a console, screens dark but one faint glow |
| c05 | 2/2 | Spacer Cult | faction | a congregant in layered black vestments and a full veil, standing in a row of identical veiled figures in a dark congregation hall, one garnet lamp above |
| c04 | 1/3 | Tamsin Reyes | character | a lone operative in a plain hooded coat and respirator, a long case over the shoulder, standing in a frontier airlock, frost on the walls, a dim strip light |
| c03 | 1/2 | Eli Kestner | character | a human fighter in frontier gear and a balaclava, a rifle slung on the back and out of focus, a radio in hand, standing in an asteroid tunnel, one work light |
| c02 | 1/2 | Collaborators | faction | a human in work gear and a vampire in a long coat standing side by side at a frontier dock, faces in shadow, the ship behind them, one dock light |
| c01 | 1/1 | The Rowan Cell | faction | a young cell fighter in patched gear and a scarf over the face, standing in an asteroid tunnel with a painted rowan-leaf mark on the wall, a hand lamp |

Dropped for later sets: Caius Marrow, Dessa Kray, Rook Solano, Wren Adair, The Hollow
Star, Charon's Drift, The Cinderfall, Midnight Earth (the world itself), Purists,
Requiem's Ledger. Caius Marrow and Wren Adair are the strongest of these when the card
list grows past 20.

## References

- Ben's Pinterest board, `https://www.pinterest.com/bk0542/midnight-earth/` (26 pins,
  read through its RSS feed on 2026-11-03). What to take: one full-length figure,
  centred and still, with a lot of empty space; dark ceremonial or cult-like layered
  costume; masks, veils and hidden faces; black, grey and bone with one accent; crescent
  moons and eclipses; monumental grey architecture. What not to take: its photographic
  rendering (most pins are photos or photoreal renders) and its flat saturated
  backgrounds. The pins are not copied into the repo; the artist re-reads the feed when
  it needs them.
- The archive's world notes, read-only: `../midnightearth-archive/Characters`,
  `Factions`, `Locations`. Each card's subject slot comes from the one-line summary at
  the top of its note.
- The archive's style tile, as above: palette anchors only.
- `explore-01` (2026-11-04), gitignored under `art/candidates/explore-01/` with a
  sidecar per prediction and seven contact sheets `sheet-a.png` to `sheet-g.png`. The
  picked predictions, so they can be regenerated after the folder is gone (all
  `flux-schnell` except `f2`):

  | Pick | Prediction | Seed | Ratio | What it settled |
  |---|---|---|---|---|
  | `a3-heavy-3v` | `ezx5xj4z2srp60d1mm5vec80b0` | 1101 | 3:4 | E1 heavy line, three values |
  | `b4-few-2x3` | `vk50w3vmphrp20d1mm6vhwbn9g` | 1201 | 2:3 | E2 aspect 2:3 |
  | `c3-garnet-lining` | `ee18kpxny1rp60d1mm7ah5qm54` | 1301 | 3:4 | E3 garnet as lining |
  | `d3-grain-none` | `cwbmc1fwhsrp00d1mm7sta06cg` | 1401 | 3:4 | E4 no grain |
  | `e2-face-bare` | `etdsz1je7nrp20d1mm8bysqsz0` | 1501 | 3:4 | E5 bare faces |
  | `f2-dev-guidance-2.5` (`flux-dev`) | `76a2ddw7fsrnc0d1mm8tvwce1w` | 1101 | 3:4 | E6 guidance 2.5 |
  | `g1-confirm-skeleton` | `5rpcq71wd1rna0d1n0v9ngs80c` | 1101 | 2:3 | E8 the skeleton above |

## Model and cost

| Verb | Model | Price | Per batch |
|---|---|---|---|
| `explore` | `black-forest-labs/flux-schnell` | $0.003 an image ($3.00 per thousand) | `explore-01` actual: 49 schnell images $0.147 plus 8 flux-dev images $0.200, $0.347 in all |
| `generate` | `black-forest-labs/flux-dev` | $0.025 an image | 20 cards x 4 variants = 80 images: $2.00 |
| LoRA references | `black-forest-labs/flux-dev` | $0.025 an image | 15 to 30 approved references at 4 variants each: $1.50 to $3.00 |

Prices read from `https://replicate.com/pricing` on 2026-11-03 and again on 2026-11-04;
the ledger is an estimate and Replicate's billing page is the truth (D3 target: $30 a
month). The account had no credit until Ben added $10 on 2026-11-04 (round 1, 1a); the
first four predictions of `explore-01` were refused with HTTP 402 and cost nothing.
`flux-dev` was chosen over `flux-1.1-pro` ($0.04) because the planned LoRA trains on
FLUX dev, so references made with it match what the LoRA will produce. Training is its
own step with its own `ROUND` and cost, once 15 to 30 references are approved.

## Open questions after `explore-01`

The eight `explore` questions are answered above (E1 to E8). Still open, for `/art
generate` and the cycle that wires art into the card face:

1. **`flux-dev` holds the ink look?** The explore guidance pair drifted painterly with
   the old prompt order. The first `generate` batch is the test of the style-first
   skeleton on `flux-dev`; if it still drifts, the opener gets shorter and more literal
   before anything else changes.
2. **Borders and signatures.** Two of four confirmation images still carried a paper
   border despite the avoid words. `generate` should expect to discard variants for it;
   if more than half a batch shows it, try "full-bleed, the image fills the frame edge
   to edge" in the opener.
3. **The card-id mapping** above (Ben confirms at `generate`), and whether faction cards
   want a second figure (Collaborators has two).
4. **Grain in Godot.** E4 moves texture out of the prompt; whether the card face gets a
   uniform grain overlay, and how it survives the mobile renderer, is cycle work.
5. **The 2:3 crop in the frame.** E2 picks 2:3 from the sheets; the first cycle that
   puts art behind the frame checks that the 3.5% top and bottom crop leaves the name
   band and the bottom corners as calm as the sheets suggest.

## Related

- [[decisions/0003-art-agent]] — the artist, the relay and the LFS pipeline
- [[planning/phase-1-tech-stack]] — D3, art on Replicate
- [[home]]
