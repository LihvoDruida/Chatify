#!/usr/bin/env python3
"""Validate shipped fonts, Ukrainian glyphs, PNGs and literal addon asset paths."""
from pathlib import Path
import re
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def main():
    fonts = sorted((ROOT / 'assets/Fonts').glob('*.ttf'))
    images = sorted((ROOT / 'assets').rglob('*.png'))
    assert fonts and images, 'missing bundled assets'
    for path in fonts:
        with TTFont(path) as font:
            cmap = font.getBestCmap()
            assert cmap and all(ord(c) in cmap for c in 'ҐґЄєІіЇї'), f'{path.name}: missing Ukrainian glyphs'
            assert 'fvar' not in font, f'{path.name}: expected static font'
    for path in images:
        with Image.open(path) as image:
            assert image.format == 'PNG' and image.width > 0 and image.height > 0, path
            image.verify()
    for path in ROOT.glob('*.lua'):
        text = path.read_text(encoding='utf-8').replace('\\\\', '/')
        for match in re.finditer(r'Interface/AddOns/Chatify/([^"\n]+\.(?:png|ttf|ogg))"', text):
            assert (ROOT / match[1]).is_file(), f'{path.name}: missing asset {match[1]}'
    for name in re.findall(r'ADDON_FONT_ROOT\s*\.\.\s*"([^"]+)"', (ROOT / 'Config.lua').read_text()):
        assert (ROOT / 'assets/Fonts' / name).is_file(), f'missing font binding: {name}'
    print(f'Asset audit: PASS ({len(fonts)} static fonts with Ukrainian glyphs, {len(images)} PNGs, asset bindings)')


if __name__ == '__main__':
    main()
