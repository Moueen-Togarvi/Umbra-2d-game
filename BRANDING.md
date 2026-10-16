# Umbra brand

Umbra tells its story without words: a boy runs from home after an
argument, vampires take him in the night forest, and he has to escape
their land. The brand is quiet in the same way. It uses black and fog,
with one warm light.

## Colour

| Token (`Palette`) | Hex | Use |
|---|---|---|
| `brandBlack` | `#0B0B0B` | Splash, title, chapter cards, app background. A hair lighter than the silhouettes. |
| `brandInk` | `#D8D4CC` | Words on the brand screens: a fog-pale ink, never pure white. |
| `lampAmber` | `#E8A84A` | **Home.** The lamp in the cottage window, the eyes in the wordmark, the rule on the cards, the icon's doorway. The only warm colour. |
| `vampireRed` | `#C21E1E` | **The vampires' eyes.** Nothing else. The last frame of the story turns the boy's eyes this colour. |
| fog greys | see `Mood` | Everything else: the world is black silhouettes in grey fog. |

Rules:
- Amber and red are rare on screen, and that is what makes them work. Use amber only for things that belong to home. Use red only for eyes.
- Never put the two colours side by side.
- There is no other hue: no blue UI and no coloured buttons.

## Type

**Cinzel** (Natanael Gama, SIL Open Font License 1.1, `assets/fonts/`) is the brand's only typeface:
- **Wordmark:** UMBRA in capitals, widely letter-spaced (0.32 em).
- **Chapter cards:** "CHAPTER ONE" small and spaced, then the chapter's name large beneath it, with a short amber rule between the two.
- **Menu:** three words, Begin · Continue · Chapters, in quiet ink that warms to amber under a finger.

The game itself has no text at all.

## Wordmark

UMBRA, with two small glowing eyes looking out of the bowl of the U:
- amber on the title
- red where the story turns dark

It is drawn in code by `WordmarkPainter` (`lib/ui/wordmark.dart`), and baked to `assets/brand/wordmark.png` for the splash by `tools/make_brand.py`.

## Icon

The boy's silhouette stands in the lit doorway of home, mapped onto the brand ramp, which runs from near-black through amber to a warm cream:
- source: `assets/raw/part1/brand_icon.png`
- the AI-generated art is listed in `tools/part1_assets.json`

`tools/make_brand.py` writes:
- the Android legacy and adaptive icons (with a near-black background)
- the web icons and the favicon
- `assets/brand/icon_1024.png`

## Screens

- **Splash:** the wordmark on `brandBlack`. Android 12 and later show the icon on `brandBlack`.
- **Title:**
  - It is laid over the live first scene, the cottage at dusk with the lamp lit and the argument behind the curtain.
  - The picture fades in first, then the wordmark and the three words.
  - There is no panel: only a soft shade behind the words.
- **Chapter cards:**
  - They appear on black between chapters.
  - Out of the title, the card is laid low over the opening scene instead.
  - They fade in and out over about three seconds.

## Art

- Everything physical is a black silhouette.
- Distance is shown by fog, not by colour.
- Generated scenery is baked to flat silhouettes by `tools/bake_silhouettes.py`:
  - the interior detail is filled
  - only the outline remains
  - openings such as windows and doors are cut back out for light to show through
- The levels and the art are original.
- The prompts never name another game.
