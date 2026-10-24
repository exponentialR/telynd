"""Build Telynd's editable logo exports and Mac icon from vector geometry.

Requires fontTools, rsvg-convert (librsvg) and macOS iconutil.
No generated raster concept is modified or traced by this script.
"""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/branding"
BLUE = "#125CFF"
INK = "#0D1C3A"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def write_svg(path, width, height, content, title="Telynd"):
    path.write_text(
        f'<svg xmlns="{SVG}" viewBox="0 0 {width} {height}" role="img" aria-label="{title}">\n'
        + content + "\n</svg>\n"
    )


def render(source, destination, width, background=None):
    args = ["rsvg-convert", "--width", str(width), "--output", str(destination)]
    if background:
        args.extend(["--background-color", background])
    subprocess.run([*args, str(source)], check=True)


def wordmark():
    font = instantiateVariableFont(TTFont(ASSETS / "source/Manrope[wght].ttf"), {"wght": 650})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    units = font["head"].unitsPerEm
    scale = 160 / units
    x = 0
    paths = []
    for letter in "Telynd":
        glyph = glyphs[cmap[ord(letter)]]
        pen = SVGPathPen(glyphs)
        glyph.draw(pen)
        paths.append(f'<path transform="translate({x:.3f} 0)" d="{pen.getCommands()}"/>')
        x += glyph.width - units * 0.016
    return f'<g transform="translate(314 175) scale({scale:.6f} {-scale:.6f})">' + "".join(paths) + "</g>", 314 + x * scale + 40


def main():
    mark = ET.parse(ASSETS / "telynd-mark.svg").getroot()
    group = mark.find(f"{{{SVG}}}g")
    assert group is not None
    geometry = ET.tostring(group, encoding="unicode")
    lettering, width = wordmark()
    lockup = '<g transform="translate(28 0)">' + geometry + "</g>"
    variants = {
        "telynd-logo-v2": (BLUE, INK),
        "telynd-logo-dark": ("#7CA5FF", "#FFFFFF"),
        "telynd-logo-black": ("#000000", "#000000"),
        "telynd-logo-white": ("#FFFFFF", "#FFFFFF"),
    }
    for name, (mark_colour, text_colour) in variants.items():
        source = ASSETS / f"{name}.svg"
        content = lockup.replace(BLUE, mark_colour) + f'<g fill="{text_colour}">{lettering}</g>'
        write_svg(source, round(width), 256, content)
        render(source, ASSETS / f"{name}.png", 1800)

    render(ASSETS / "telynd-mark.svg", ASSETS / "telynd-mark.png", 1024)
    white_mark = geometry.replace(BLUE, "#FFFFFF")
    icon = (f'<rect x="64" y="64" width="896" height="896" rx="196" fill="{INK}"/>'
            + '<g transform="translate(244.48 244.48) scale(2.09)">' + white_mark + "</g>")
    write_svg(ASSETS / "telynd-app-icon.svg", 1024, 1024, icon, "Telynd app icon")
    render(ASSETS / "telynd-app-icon.svg", ASSETS / "telynd-app-icon.png", 1024)
    with tempfile.TemporaryDirectory() as temp:
        iconset = Path(temp) / "Telynd.iconset"
        iconset.mkdir()
        for logical in [16, 32, 128, 256, 512]:
            for density in [1, 2]:
                suffix = "@2x" if density == 2 else ""
                render(ASSETS / "telynd-app-icon.svg", iconset / f"icon_{logical}x{logical}{suffix}.png", logical * density)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ASSETS / "Telynd.icns")], check=True)

    # A review sheet uses the same vector paths at real small sizes. All logos
    # above remain standalone SVGs with outlined lettering and no linked fonts.
    sheet = [f'<rect width="1440" height="980" fill="#F5F7FC"/>']
    sheet += [f'<text x="72" y="78" font-family="sans-serif" font-size="18" letter-spacing="3" fill="{INK}">TELYND / OPEN PORTAL</text>']
    sheet += ['<rect x="48" y="112" width="1344" height="310" rx="24" fill="white"/>',
              '<g transform="translate(152 137) scale(1.12)">', lockup,
              f'<g fill="{INK}">{lettering}</g></g>',
              f'<rect x="48" y="446" width="880" height="300" rx="24" fill="{INK}"/>',
              '<g transform="translate(90 495) scale(.81)">', lockup.replace(BLUE, "#7CA5FF"),
              f'<g fill="white">{lettering}</g></g>',
              '<rect x="952" y="446" width="440" height="300" rx="24" fill="white"/>',
              '<g transform="translate(1026 449) scale(.285)">', icon, '</g>',
              f'<text x="72" y="804" font-family="sans-serif" font-size="17" fill="{INK}">Symbol at 16, 24, 32 and 64 pixels</text>']
    for x, size in [(72, 16), (136, 24), (208, 32), (296, 64)]:
        sheet.append(f'<g transform="translate({x} 835) scale({size / 256})">{geometry}</g>')
    sheet += [f'<g transform="translate(560 814) scale(.4)">{geometry.replace(BLUE, "#000000")}</g>',
              '<rect x="730" y="806" width="140" height="120" rx="12" fill="black"/>',
              f'<g transform="translate(749 815) scale(.4)">{white_mark}</g>']
    # Each group reuses #portal; give every instance its own reference in the
    # combined sheet to avoid cross-instance fill/transform ambiguity.
    sheet_root = ET.fromstring(f'<svg xmlns="{SVG}" viewBox="0 0 1440 980">' + "".join(sheet) + '</svg>')
    for index, group in enumerate(sheet_root.iter(f"{{{SVG}}}g")):
        path = next((child for child in group if child.get("id") == "portal"), None)
        if path is not None:
            path.set("id", f"portal-{index}")
            for child in group:
                if child.tag == f"{{{SVG}}}use": child.set("href", f"#portal-{index}")
    ET.ElementTree(sheet_root).write(ASSETS / "telynd-brand-review.svg", encoding="unicode")
    render(ASSETS / "telynd-brand-review.svg", ASSETS / "telynd-brand-review.png", 1440)
    print("Built Telynd logo variants, outlined wordmarks, small-size review and app icon.")


if __name__ == "__main__":
    main()
