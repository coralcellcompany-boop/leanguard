"""Rasterize the supplied prototype's simple polygon SVG into native icons.
Run: python3 -m pip install pillow && python3 tool/generate_app_icons.py
No design is synthesized: these are the original prototype favicon paths.
"""
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/app_icon.svg'

def polygons(path):
    tokens = iter(re.findall(r'[MmLlHhVvZz]|-?\d+(?:\.\d+)?', path))
    current, origin, points = [0., 0.], [0., 0.], []
    for command in tokens:
        if command.lower() == 'z':
            yield points
            current, points = origin.copy(), []
            continue
        if command.lower() in ('m', 'l'):
            x, y = float(next(tokens)), float(next(tokens))
            current = [x + current[0], y + current[1]] if command.islower() else [x, y]
        elif command.lower() == 'h':
            x = float(next(tokens)); current[0] = current[0] + x if command.islower() else x
        elif command.lower() == 'v':
            y = float(next(tokens)); current[1] = current[1] + y if command.islower() else y
        else:
            raise ValueError('Unsupported path command: ' + command)
        if command.lower() == 'm':
            origin = current.copy()
        points.append(tuple(current))

def render(path, size):
    # App Store icons require an opaque full-bleed square background.
    resolution = max(1024, size * 4)
    image = Image.new('RGB', (resolution, resolution), '#111312')
    draw = ImageDraw.Draw(image)
    for element in ET.parse(SOURCE).getroot():
        if element.tag.endswith('path'):
            for points in polygons(element.attrib['d']):
                draw.polygon([(x * resolution / 64, y * resolution / 64) for x, y in points], fill=element.attrib['fill'])
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)

catalog = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for icon in json.loads((catalog / 'Contents.json').read_text())['images']:
    if 'filename' in icon:
        render(catalog / icon['filename'], round(float(icon['size'].split('x')[0]) * float(icon['scale'][:-1])))
for scale, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    render(ROOT / f'android/app/src/main/res/mipmap-{scale}/ic_launcher.png', size)
for suffix, scale in [('', 1), ('@2x', 2), ('@3x', 3)]:
    render(ROOT / f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', 96 * scale)
