# Telynd identity

The selected direction is **Open portal**: two open frames with a continuous
space between them. It represents entering a remote workspace. The final mark
uses two matching shapes rotated by 180 degrees, consistent curves and a single
flat colour. The original generated concepts are retained in `concepts/`.

## Files

- `telynd-logo-v2.svg` and `.png`: transparent primary logo, cobalt mark and navy wordmark.
- `telynd-logo-dark.svg` and `.png`: pale blue mark and white wordmark for dark backgrounds.
- `telynd-logo-black.svg` and `telynd-logo-white.svg`: one-colour logos.
- `telynd-mark.svg` and `.png`: the standalone symbol.
- `telynd-app-icon.svg`, `.png` and `Telynd.icns`: the white mark on a navy Mac app tile.
- `telynd-brand-review.png`: the light and dark logos, app icon, monochrome marks and small-size comparison.

Logo SVGs contain real vector geometry and outlined lettering. They do not embed
a bitmap or require a font at display time. PNGs are exports of those SVGs.
The initial `telynd-logo.png` remains a saved first concept.

## Colours and spacing

| Role | Colour |
| --- | --- |
| Primary cobalt | `#125CFF` |
| Ink navy | `#0D1C3A` |
| Mark on dark backgrounds | `#7CA5FF` |
| Reversed lettering | `#FFFFFF` |

Keep clear space of at least one quarter of the symbol's width around the
standalone mark. Use the standalone symbol for small icons; the wordmark is
intended for larger placements. The review sheet includes symbols at 16, 24,
32 and 64 pixels. The app icon includes transparent outer padding.

## Provenance and regeneration

The three concept PNGs were generated with the built-in image generation tool.
Their exact prompts are in `concept-prompts.txt`. The selected
concept was then rebuilt as geometric SVG paths and font outlines; the SVGs
are not automated raster traces.

The wordmark uses outlined Manrope at weight 650 with adjusted letter spacing.
The unmodified variable font and its SIL Open Font Licence are included in
`source/`, fetched from the [Google Fonts Manrope directory](https://github.com/google/fonts/tree/main/ofl/manrope).
The font licence covers that font. Telynd's code and original branding sources
use the [MIT licence](../../LICENSE).

To regenerate exports on macOS with fontTools, librsvg and iconutil installed:

```sh
python3 scripts/build-branding.py
```

The main app build consumes the committed `Telynd.icns` and does not need these
branding dependencies. The app header uses the light and dark PNG exports.
