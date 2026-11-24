"""Generates the uikit textures (original art, drawn here with a seeded noise; no third-party or Minecraft assets).
Run:  python3 -I tools/make_ui_textures.py     -> mods/uikit/textures/uikit_*.png (16x16, 9-slice with a 4 px middle border)
All colours are in one table so a theme change = edit the table and rerun."""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mods', 'uikit', 'textures')
S = 16

def bevel(fill, light, dark, outer, noise=7, seed=1, glow=None):
    rnd = random.Random(seed)
    px = []
    for y in range(S):
        row = []
        for x in range(S):
            edge = min(x, y, S - 1 - x, S - 1 - y)
            if edge == 0:
                c = outer
            elif edge <= 2:
                # top/left light, bottom/right dark; corners go to the dark side so the frame reads as raised
                if (y <= 2 and y <= x and y < S - 1 - x) or (x <= 2 and x < y and x < S - 1 - y):
                    c = light
                else:
                    c = dark
                if y > S - 4 and x < 3: c = dark
            else:
                n = rnd.randint(-noise, noise)
                c = tuple(max(0, min(255, fill[i] + n)) for i in range(3))
            row.append(tuple(c) + (255,))
        px.append(row)
    return px

def panel(fill, border):
    px = []
    for y in range(S):
        row = []
        for x in range(S):
            edge = min(x, y, S - 1 - x, S - 1 - y)
            row.append(border if edge == 0 else fill)
        px.append(row)
    return px

def field(fill, border):
    px = []
    for y in range(S):
        row = []
        for x in range(S):
            edge = min(x, y, S - 1 - x, S - 1 - y)
            row.append(border if edge == 0 else fill)
        px.append(row)
    return px

THEME = {
    'button':          dict(fill=(118, 118, 118), light=(176, 176, 176), dark=(72, 72, 72), outer=(18, 18, 18), seed=1),
    'button_hover':    dict(fill=(134, 138, 156), light=(196, 200, 222), dark=(84, 86, 102), outer=(18, 18, 18), seed=2),
    'button_pressed':  dict(fill=(98, 98, 98), light=(66, 66, 66), dark=(150, 150, 150), outer=(18, 18, 18), seed=3),
    'button_disabled': dict(fill=(58, 58, 58), light=(84, 84, 84), dark=(40, 40, 40), outer=(18, 18, 18), seed=4, noise=3),
}

os.makedirs(OUT, exist_ok=True)
for name, kw in THEME.items():
    pnglib.write(os.path.join(OUT, 'uikit_%s.png' % name), S, S, bevel(**kw))
pnglib.write(os.path.join(OUT, 'uikit_panel.png'), S, S, panel((0, 0, 0, 70), (150, 150, 150, 200)))
pnglib.write(os.path.join(OUT, 'uikit_panel_solid.png'), S, S, panel((24, 24, 28, 238), (150, 150, 150, 255)))
pnglib.write(os.path.join(OUT, 'uikit_field.png'), S, S, field((0, 0, 0, 255), (160, 160, 160, 255)))
print('wrote', sorted(os.listdir(OUT)))
