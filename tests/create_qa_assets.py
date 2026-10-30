#!/usr/bin/env python3
"""Generate small, reproducible Premiere feather-effect QA sources and FCP7 XML.

Requires Pillow. All generated sources are local synthetic test patterns.
Run from any directory; outputs live in edge-feather/verification/assets.
"""

from __future__ import annotations

import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont


WIDTH, HEIGHT, FPS, FRAMES = 960, 540, 30, 150
ASSETS = Path(__file__).resolve().parents[1] / "verification" / "assets"
MAGENTA = (235, 0, 180, 255)
CYAN = (0, 210, 235, 255)


def font(size: int) -> ImageFont.ImageFont:
    for name in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        if Path(name).is_file():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default(size=size)


def text_center(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str,
                size: int, color: tuple[int, ...]) -> None:
    draw.text(xy, text, font=font(size), fill=color, anchor="mm")


def generate_images() -> None:
    checker = Image.new("RGBA", (WIDTH, HEIGHT), MAGENTA)
    draw = ImageDraw.Draw(checker)
    for y in range(0, HEIGHT, 60):
        for x in range(0, WIDTH, 60):
            if (x // 60 + y // 60) % 2:
                draw.rectangle((x, y, x + 59, y + 59), fill=CYAN)
    checker.save(ASSETS / "checker-background.png", compress_level=9)

    foreground = Image.new("RGBA", (WIDTH, HEIGHT), (255, 255, 255, 255))
    draw = ImageDraw.Draw(foreground)
    text_center(draw, (480, 45), "TOP", 26, (175, 25, 25, 255))
    text_center(draw, (480, 495), "BOTTOM", 26, (25, 125, 35, 255))
    text_center(draw, (85, 270), "LEFT", 26, (30, 55, 175, 255))
    text_center(draw, (875, 270), "RIGHT", 26, (135, 40, 155, 255))
    text_center(draw, (480, 254), "EDGE FEATHER QA", 25, (35, 35, 35, 255))
    text_center(draw, (480, 286), "960 x 540  /  30 fps  /  5 seconds", 15, (65, 65, 65, 255))
    # A restrained center target helps identify framing without changing the
    # large white regions used for objective pixel samples.
    draw.line((467, 320, 493, 320), fill=(120, 120, 120, 255), width=1)
    draw.line((480, 307, 480, 333), fill=(120, 120, 120, 255), width=1)
    foreground.save(ASSETS / "opaque-foreground.png", compress_level=9)

    semi = foreground.copy()
    semi.putalpha(128)
    semi.save(ASSETS / "semitransparent-foreground.png", compress_level=9)


def node(parent: ET.Element, tag: str, text: object | None = None,
         **attributes: str) -> ET.Element:
    child = ET.SubElement(parent, tag, attributes)
    if text is not None:
        child.text = str(text)
    return child


def rate(parent: ET.Element) -> None:
    element = node(parent, "rate")
    node(element, "timebase", FPS)
    node(element, "ntsc", "FALSE")


def sample_characteristics(parent: ET.Element) -> None:
    element = node(parent, "samplecharacteristics")
    rate(element)
    node(element, "width", WIDTH)
    node(element, "height", HEIGHT)
    node(element, "anamorphic", "FALSE")
    node(element, "pixelaspectratio", "square")
    node(element, "fielddominance", "none")


def clip(track: ET.Element, name: str, filename: str, number: int) -> None:
    element = node(track, "clipitem", id=f"edge-feather-qa-clip-{number}")
    node(element, "name", name)
    node(element, "enabled", "TRUE")
    node(element, "duration", FRAMES)
    rate(element)
    node(element, "start", 0)
    node(element, "end", FRAMES)
    node(element, "in", 0)
    node(element, "out", FRAMES)
    node(element, "stillframe", "TRUE")
    node(element, "anamorphic", "FALSE")
    node(element, "pixelaspectratio", "square")
    node(element, "alphatype", "straight")
    node(element, "compositemode", "normal")
    file = node(element, "file", id=f"edge-feather-qa-file-{number}")
    node(file, "name", filename)
    node(file, "pathurl", (ASSETS / filename).as_uri())
    rate(file)
    node(file, "duration", FRAMES)
    node(file, "stillimage", "TRUE")
    video = node(node(file, "media"), "video")
    node(video, "duration", FRAMES)
    sample_characteristics(video)
    source = node(element, "sourcetrack")
    node(source, "mediatype", "video")
    node(source, "trackindex", 1)


def generate_xml(filename: str, sequence_name: str, foreground_file: str) -> None:
    root = ET.Element("xmeml", {"version": "5"})
    sequence = node(root, "sequence", id="edge-feather-qa-sequence")
    node(sequence, "name", sequence_name)
    node(sequence, "duration", FRAMES)
    rate(sequence)
    timecode = node(sequence, "timecode")
    rate(timecode)
    node(timecode, "string", "00:00:00:00")
    node(timecode, "frame", 0)
    node(timecode, "displayformat", "NDF")
    video = node(node(sequence, "media"), "video")
    sample_characteristics(node(video, "format"))
    background_track = node(video, "track")
    clip(background_track, "QA Checker Background", "checker-background.png", 1)
    node(background_track, "enabled", "TRUE")
    node(background_track, "locked", "FALSE")
    foreground_track = node(video, "track")
    clip(foreground_track, "QA Foreground - Apply Edge Feather Here", foreground_file, 2)
    node(foreground_track, "enabled", "TRUE")
    node(foreground_track, "locked", "FALSE")
    ET.indent(root, space="  ")
    payload = ET.tostring(root, encoding="unicode")
    (ASSETS / filename).write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n' + payload + "\n",
        encoding="utf-8",
    )


def verify() -> None:
    for filename, alpha in (("opaque-foreground.png", 255),
                            ("semitransparent-foreground.png", 128)):
        with Image.open(ASSETS / filename) as image:
            image.load()
            assert image.size == (WIDTH, HEIGHT)
            assert image.mode == "RGBA"
            assert image.getextrema()[3] == (alpha, alpha)
            assert image.getpixel((0, 0)) == (255, 255, 255, alpha)
            assert image.getpixel((959, 539)) == (255, 255, 255, alpha)
    with Image.open(ASSETS / "checker-background.png") as image:
        assert image.size == (WIDTH, HEIGHT)
        assert image.getpixel((0, 0)) == MAGENTA
        assert image.getpixel((60, 0)) == CYAN
        assert image.getextrema()[3] == (255, 255)
    for filename in ("edge-feather-qa.xml", "edge-feather-qa-semitransparent.xml"):
        tree = ET.parse(ASSETS / filename)
        sequence = tree.getroot().find("sequence")
        assert sequence is not None
        assert sequence.findtext("duration") == str(FRAMES)
        clips = sequence.findall("media/video/track/clipitem")
        assert len(clips) == 2
        for item in clips:
            assert item.findtext("start") == "0"
            assert item.findtext("end") == str(FRAMES)
            assert item.findtext("file/pathurl").startswith("file:///")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    generate_images()
    generate_xml("edge-feather-qa.xml", "Edge Feather QA - Opaque", "opaque-foreground.png")
    generate_xml("edge-feather-qa-semitransparent.xml", "Edge Feather QA - Existing Alpha",
                 "semitransparent-foreground.png")
    verify()
    manifest = {
        "dimensions": [WIDTH, HEIGHT], "fps": FPS, "frames": FRAMES, "seconds": FRAMES / FPS,
        "main_xml": str(ASSETS / "edge-feather-qa.xml"),
        "existing_alpha_xml": str(ASSETS / "edge-feather-qa-semitransparent.xml"),
        "apply_effect_to": "V2 foreground clip",
        "background_rgba": {"0,0": MAGENTA, "60,0": CYAN},
        "foreground_rgba_at_unlabelled_pixels": [255, 255, 255, 255],
        "existing_alpha_rgba_at_unlabelled_pixels": [255, 255, 255, 128],
        "expected_default": "Opaque sequence shows white foreground. Existing-alpha sequence shows checker through 128/255 alpha foreground.",
        "expected_top_only": "Only top fades to checker; bottom and side midpoints stay white. Top outermost pixel exposes checker fully.",
    }
    (ASSETS / "qa-assets.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Verified 3 RGBA PNGs and 2 FCP7 XML sequences in {ASSETS}")


if __name__ == "__main__":
    main()
