---
type: reference
tags: [art, reference, cards]
status: seedling
related: ["[[decisions/0003-art-agent]]", "[[planning/phase-1-tech-stack]]", "[[home]]"]
created: 2026-11-03
updated: 2026-11-03
uid: 5bf8298d-cd5f-4d0b-8566-50f3839f1ed3
linear:
supersedes:
---

# Art direction

> What every Midnight Earth card illustration looks like, decided with Ben on 2026-11-03
> in the `/art direction` interview, with the prompt skeleton and model every `/art
> explore` and `/art generate` batch starts from.

## Decisions

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
| 3.2 | Background | **Atmospheric place** behind the figure (Nocturne's skyline, the Iron Grave, haze, a distant light), not a flat field |
| 3.3 | Model for `generate` | (a) `black-forest-labs/flux-dev`, $0.025 an image |
| 3.4 | No-gos | (a) The usual card-game set (below) |
| 4.1 | The 20 subjects | (a) 13 characters, 3 factions, 4 locations (list below) |
| 4.2 | Faces | (a) Mostly hidden (masks, veils, hoods, helmets); bare faces only for the leads |
| 4.3 | Shot | (a) Full-length, feet visible, figure about 60% of the card height, centred |

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
is rationed: blood, a House sigil, a warning light, the inside of a hood. Never more than
one garnet idea per card. No other saturated hue.

**Rendering.** Ink and flat tone. A confident black ink line does the drawing; the colour
is two or three flat values (dark, mid, light) with no gradients, no airbrush, no
painterly brushwork, no photographic detail. Shadows are solid shapes, not soft.
Surface texture is coarse paper or screen-print grain, visible but not noisy. The feel is
a printed poster or a woodcut, not a digital painting. This is the cheapest look to keep
consistent across 20 cards and it reads clean at 2.5 x 3.5 units.

**Figure.** Full-length, feet visible, centred, still, facing the viewer or in
three-quarter view, about 60% of the card height. Posed like the board: composed,
ceremonial, weight on both feet, hands visible and doing something small (holding a
relic, resting on a blade, pressed together). Costume is dark, layered, ceremonial or
cult-like: robes, hoods, veils, chains, headdresses, work gear with ritual trim. Faces
are mostly hidden by masks, veils, hoods or helmets; bare faces only for Livia Vesperi,
Corvin Vesperi, Imogen Hask, Mara Voss and Perpetua Vane, and even those in shadow.

**Background.** An atmospheric place, simplified to the same two or three flat values:
Nocturne's House spires through haze, the undercity, a cathedral-ship's nave, the
belt rock, the iron orb. One distant light source at most. The background stays
quieter than the figure: fewer lines, lower contrast, so the figure's silhouette reads
first.

**Framing and calm zones.** The art is full-bleed behind the card frame. The frame
carries the name, cost and power, so every prompt keeps three zones uncluttered: the
top band (about the top 12% of the image) for the name, and the bottom-left and
bottom-right corners (about 18% x 12% each) for cost and power. In practice: the figure
sits in the centre band, the background's darkest, flattest value fills the top edge and
the bottom corners, and nothing of interest (a face, a hand, a light source) is placed
there. The 5:7 face may crop a little from each side of the generated image, so nothing
important sits within 5% of the left or right edge either.

**Recurring motifs** (from the board, use sparingly): a crescent moon or an eclipse
behind the head; monumental grey architecture; a single figure in a wide empty place.

## No-gos

From the artist's brief: no text, letters or numbers in the image; no living artists,
real brands, logos or copyrighted characters in prompts. Added by Ben (3.4 a): no gore
beyond implied blood; no sexualised figures; no modern firearms as the focal object; no
real-looking faces of real people (masks and veils help here). From the look itself: no
gradients or soft painterly rendering, no lilac, cyan or blush, no second saturated hue
beside garnet, no busy top band or bottom corners.

## Prompt skeleton

Every prompt is the subject slot followed by the fixed style block, in this order. The
style block is the same string for every card so the LoRA later learns one look.

**Subject slot** (one or two sentences, per card):

```
<who>, <what they wear and hold, face hidden how>, standing full-length and centred,
<pose>, in <place>, <one background detail>, <where the single light comes from>.
```

**Fixed style block** (verbatim, after the subject slot):

```
Ink and flat tone illustration, confident black ink line, two or three flat colour
values, no gradients, no painterly brushwork, solid shadow shapes, coarse paper and
screen-print grain. Palette: obsidian black, deep plum and steel blue-grey shadows, thin
bone-ivory moonlight, one garnet red accent only. Gothic science-fiction noir, permanent
night, near-future technology beside ritual. Full-length figure about 60% of the frame
height, feet visible, composed and still, background simplified and quieter than the
figure, darkest flat value along the top edge and in the bottom corners, nothing of
interest near the edges. Portrait card illustration, no text, no letters, no logos.
```

**Avoid list** (FLUX has no negative prompt; put these as "no ..." at the end of the
prompt only when a batch shows the problem): photorealistic, 3D render, soft gradients,
lens blur, lilac, cyan, pink, multiple light sources, cropped feet, text.

**Parameters** (`black-forest-labs/flux-dev`, an official model, through
`create_models_predictions` with `Prefer: wait`; read the schema with `get_models`
before the first call of a batch):

| Input | Value | Why |
|---|---|---|
| `aspect_ratio` | `3:4` | flux-dev takes no width/height; 3:4 (0.75) is the nearest listed portrait ratio to 5:7 (0.714). The frame crops about 5% off the sides. Record this in each sidecar. |
| `megapixels` | `1` | About 896 x 1152 at 3:4 |
| `num_outputs` | `4` | Four variants per asset in one prediction (the `generate` default) |
| `num_inference_steps` | `28` | Model default |
| `guidance` | `3.5` | Model default; try 2.5 to 3 if the line goes stiff |
| `output_format` | `png` | Lossless for approval |
| `seed` | chosen per prediction and recorded | Approved images must be reproducible |
| `go_fast` | `false` | Full-precision run for assets |

`explore` uses the same prompt and ratio on `black-forest-labs/flux-schnell`
(`num_inference_steps` 4, `go_fast` true) with `num_outputs` 4.

## The 20 cards

Ben chose the subjects (4.1 a). The card ids in `godot/engine/data/cards.json` are
placeholders with a cost and power each; the mapping below pairs the weightiest subjects
with the highest costs and is a **proposal for `/art generate`** to confirm, not a
decision. Subject slots are drafts for the artist to tune per batch.

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
| c09 | 3/3 | Thessaly Vesperi | character | a young woman in formal House vestments with a close veil over the face, standing very straight, hands clasped, in a chapel of the cathedral-ship, candles, a garnet sigil on the veil |
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
  backgrounds, which Ben turned down in favour of ink and flat tone and an atmospheric
  place. The pins are not copied into the repo; the artist re-reads the feed when
  it needs them.
- The archive's world notes, read-only: `../midnightearth-archive/Characters`,
  `Factions`, `Locations`. Each card's subject slot comes from the one-line summary at
  the top of its note.
- The archive's style tile, as above: palette anchors only.

## Model and cost

| Verb | Model | Price | Per batch |
|---|---|---|---|
| `explore` | `black-forest-labs/flux-schnell` | $0.003 an image ($3.00 per thousand) | 50-image cap: about $0.15 |
| `generate` | `black-forest-labs/flux-dev` | $0.025 an image | 20 cards x 4 variants = 80 images: $2.00 |
| LoRA references | `black-forest-labs/flux-dev` | $0.025 an image | 15 to 30 approved references at 4 variants each: $1.50 to $3.00 |

Prices read from `https://replicate.com/pricing` on 2026-11-03; the ledger is an estimate
and Replicate's billing page is the truth (D3 target: $30 a month). `flux-dev` was
chosen over `flux-1.1-pro` ($0.04) because the planned LoRA trains on FLUX dev, so
references made with it match what the LoRA will produce. Training is its own step with
its own `ROUND` and cost, once 15 to 30 references are approved.

## Open questions for `/art explore`

The 50-image schnell pass should answer these with pictures, four variants per
question, and the answers go back into this note:

1. **Line weight.** Heavy woodcut line versus fine pen line, same subject. Which holds
   at card size and which FLUX keeps consistent?
2. **Value count.** Two flat values plus ivory versus three plus ivory. Does the third
   value help the background recede or just add mud?
3. **How much place.** Three background densities for one subject (bare, a few shapes,
   a full skyline). Where does the top band stop being calm?
4. **Garnet.** The accent as a sigil, as a light source, and as a costume lining, on the
   same figure. Which reads as the deck's signature without pulling the eye off the face?
5. **Grain.** Paper texture versus screen-print halftone versus none. Which survives
   the Godot import and the card's size on an iPhone?
6. **Faces.** One hidden face (mask, veil, hood) and one bare face in shadow, to see how
   far flux-dev can be trusted with the five bare-faced leads.
7. **Aspect.** Confirm `3:4` crops cleanly to 5:7 with the calm zones intact; if not,
   test `2:3` and compose taller.
8. **Guidance.** 3.5 versus 2.5 on the same seed, for stiffness in the line.

Also open, outside `explore`: the card-id mapping above (Ben confirms at `generate`),
and whether faction cards want a second figure (Collaborators has two).

## Related

- [[decisions/0003-art-agent]] — the artist, the relay and the LFS pipeline
- [[planning/phase-1-tech-stack]] — D3, art on Replicate
- [[home]]
