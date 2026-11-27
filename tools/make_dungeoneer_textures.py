#!/usr/bin/env python3
"""Original 16x16 textures for Dungeoneer (dev-time; output committed in mods/dungeoneer/textures). Run: python3 -I tools/make_dungeoneer_textures.py"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglib
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mods', 'dungeoneer', 'textures')

def shade(c, d): return tuple(max(0, min(255, v + d)) for v in c[:3]) + (255,)

def brick():
    rnd = random.Random(11); base = (62, 58, 72, 255); mortar = (30, 28, 38, 255); px = []
    for y in range(16):
        row = []
        for x in range(16):
            course = y // 4                      # 4 rows of bricks, offset every other row
            xo = (x + (4 if course % 2 else 0)) % 8
            if y % 4 == 3 or xo == 7: row.append(mortar)
            else: row.append(shade(base, rnd.randint(-7, 7) + (course % 2) * 5))
        px.append(row)
    return px

def floor():
    rnd = random.Random(23); a = (74, 70, 86, 255); b = (66, 62, 78, 255); seam = (34, 32, 44, 255); px = []
    for y in range(16):
        row = []
        for x in range(16):
            if x % 8 == 7 or y % 8 == 7: row.append(seam)
            else: row.append(shade(a if ((x // 8) + (y // 8)) % 2 == 0 else b, rnd.randint(-5, 5)))
        px.append(row)
    return px

def lantern():
    rnd = random.Random(5); frame = (40, 36, 30, 255); px = []
    for y in range(16):
        row = []
        for x in range(16):
            if x in (0, 15) or y in (0, 15) or x in (7, 8) and y % 5 == 0: row.append(frame)
            else:
                d = abs(x - 7.5) + abs(y - 7.5)
                row.append((255, int(236 - d * 5), int(120 - d * 6), 255) if d < 11 else (214, 150, 60, 255))
        px.append(row)
    return px

def frame():
    px = brick(); rnd = random.Random(31)
    for y in range(16):
        for x in range(16):
            edge = min(x, y, 15 - x, 15 - y)
            if edge == 0: px[y][x] = (26, 70, 74, 255)
            elif edge == 1: px[y][x] = (44, 150, 150, 255)
            elif edge == 2: px[y][x] = (30, 92, 98, 255)
    return px

def portal():
    rnd = random.Random(7); px = []
    for y in range(16):
        row = []
        for x in range(16):
            v = (x * 3 + y * 5) % 16
            a = 150 + (v * 4) % 60
            row.append((40 + v * 3, 190 + (v * 2) % 50, 200 + (v * 3) % 50, a))
        px.append(row)
    return px

def key(tint, gem):
    px = [[(0, 0, 0, 0)] * 16 for _ in range(16)]
    def dot(x, y, c): px[y][x] = c
    dark = shade(tint, -60)
    for x in range(3, 13): dot(x, 8, tint); dot(x, 9, dark)           # shaft (horizontal)
    for (x, y) in ((3, 5), (4, 4), (5, 4), (6, 5), (6, 6), (5, 7), (4, 7), (3, 6)): dot(x, y, tint)  # bow
    dot(4, 5, gem); dot(5, 5, gem); dot(4, 6, gem); dot(5, 6, gem)     # gem in the bow
    for (x, y) in ((11, 10), (11, 11), (11, 12), (9, 10), (9, 11)): dot(x, y, tint)  # teeth
    for (x, y) in ((11, 12), (9, 11)): dot(x, y, dark)
    return px

def chest(kind):
    rnd = random.Random(41); wood = (92, 66, 52, 255); band = (40, 130, 134, 255); dark = (48, 34, 28, 255); px = []
    for y in range(16):
        row = []
        for x in range(16):
            if kind == 'top': c = shade(wood, rnd.randint(-6, 6)); edge = min(x, y, 15 - x, 15 - y) <= 1
            else: c = shade(wood, rnd.randint(-6, 6) + (y % 4 == 3) * -14); edge = x in (0, 15) or y in (0, 15)
            if edge: c = dark
            if kind != 'top' and y in (6, 7): c = band
            if kind == 'front' and 6 <= x <= 9 and 5 <= y <= 9: c = (214, 190, 120, 255) if (x in (7, 8) and y in (6, 7, 8)) else dark
            row.append(c)
        px.append(row)
    return px

os.makedirs(out, exist_ok=True)
for kind in ('top', 'side', 'front'): pnglib.write(os.path.join(out, 'dungeoneer_chest_' + kind + '.png'), 16, 16, chest(kind))
KEYS = (('dungeoneer_key_1', (214, 190, 120, 255), (200, 200, 205, 255)), ('dungeoneer_key_2', (214, 190, 120, 255), (90, 230, 235, 255)),
        ('dungeoneer_key_3', (214, 190, 120, 255), (70, 220, 110, 255)), ('dungeoneer_key_4', (120, 100, 140, 255), (255, 120, 90, 255)))
for name, tint, gem in KEYS:
    pnglib.write(os.path.join(out, name + '.png'), 16, 16, key(tint, gem))
pnglib.write(os.path.join(out, 'dungeoneer_frame.png'), 16, 16, frame())
pnglib.write(os.path.join(out, 'dungeoneer_portal.png'), 16, 16, portal())
for name, fn in (('dungeoneer_brick', brick), ('dungeoneer_floor', floor), ('dungeoneer_lantern', lantern)):
    pnglib.write(os.path.join(out, name + '.png'), 16, 16, fn())
print('written', os.listdir(out))
