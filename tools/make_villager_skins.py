#!/usr/bin/env python3
"""Villager skins for the populations mod, built from Mineclonia's own boy and girl skin layers (mcl_skins: base, hair, top, bottom, eyes,
mouth, footwear + colour masks) recoloured with the in-game dye colours.
Credits: the layers are by MrRar (CC BY-SA 4.0) and adapted from the "Pixel Perfection" resource pack by XSSheep (CC BY-SA 4.0), see
mcl_skins/media_credits.txt; the generated skins carry the same licence (mods/populations/textures/LICENSE.txt)."""
import sys, os, re, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglib as P

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, 'reference/mineclonia/mods/PLAYER/mcl_skins/textures')
DYES_LUA = os.path.join(ROOT, 'reference/mineclonia/mods/ITEMS/mcl_dyes/init.lua')
OUT = os.path.join(ROOT, 'mods/populations/textures')

# ---- the choice (edit here) ------------------------------------------------------------------------------------------
TONE = {'steve': ('b47a57', 'steve'), 'alex': ('eeb592', 'alex')}  # Mineclonia's own boy / girl skin colours (mcl_skins.base_color[2] / [1])
HAIR_COLORS = {  # name -> rgb
    'black': '151515', 'brown': '7b5232', 'blonde': 'e2bc7b',
}
HAIR_STYLES = {'steve': ['hair_2'], 'alex': ['hair_1']}  # Mineclonia's own boy / girl hair
HAIR_OF = {'steve': ['brown', 'black'], 'alex': ['black', 'blonde', 'brown']}
TOP_STYLE = 'top_1'
BOTTOM_STYLES = ['bottom_1']
EYE = {'steve': 'eye_2', 'alex': 'eye_1'}
MOUTH = {'steve': 'mouth_1', 'alex': None}
FOOTWEAR = 'footwear_1'
COUNT = {'steve': 150, 'alex': 210}  # how many different skins to make per kind (a seeded random pick of all combinations)
ALL_DYES = None  # filled from mcl_dyes
TOPS = {'steve': ['white', 'silver', 'grey', 'black', 'brown', 'red', 'orange', 'blue', 'light_blue', 'cyan', 'green'], 'alex': None}  # None = every dye
BOTTOMS = {'steve': ['black', 'grey', 'brown', 'blue', 'silver', 'white'],
           'alex': ['black', 'grey', 'silver', 'white', 'brown', 'blue', 'light_blue', 'purple']}
# -------------------------------------------------------------------------------------------------------------------------

def dyes():
    s = open(DYES_LUA).read().split('mcl_dyes.colors = {')[1].split('\n}\n')[0]
    return {m.group(1): m.group(2)[1:] for m in re.finditer(r'\["(\w+)"\] = \{.*?rgb = "(#\w+)"', s, re.S)}

def rgb(h): return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def layer(name, color):
    """(solid colour where the mask is opaque) with the texture over it; or just the texture when there is no mask."""
    _, _, tex = P.read(os.path.join(SKINS, 'mcl_skins_%s.png' % name))
    mpath = os.path.join(SKINS, 'mcl_skins_%s_mask.png' % name)
    out = [[(0, 0, 0, 0)] * 64 for _ in range(32)]
    if color and os.path.exists(mpath):
        _, _, mask = P.read(mpath)
        c = rgb(color)
        for y in range(32):
            for x in range(64):
                if mask[y][x][3] > 0: out[y][x] = c + (255,)
    over(out, tex)
    return out

def over(dst, src):
    for y in range(len(dst)):
        for x in range(len(dst[0])):
            s = src[y][x]; a = s[3] / 255
            if a == 0: continue
            d = dst[y][x]; da = d[3] / 255
            oa = a + da * (1 - a)
            dst[y][x] = tuple(int((s[i] * a + d[i] * da * (1 - a)) / oa) for i in range(3)) + (int(oa * 255 + 0.5),)

def compose(kind, hairstyle, hair, top, bstyle, bottom):
    img = [[(0, 0, 0, 0)] * 64 for _ in range(32)]
    tone, _ = TONE[kind]
    parts = [(10, layer('base_1', tone)), (30, layer(EYE[kind], None)),
             (50, layer(bstyle, bottom)), (55, layer(FOOTWEAR, None)), (60, layer(TOP_STYLE, top)), (70, layer(hairstyle, hair))]
    if MOUTH[kind]: parts.append((40, layer(MOUTH[kind], None)))
    for _, l in sorted(parts, key=lambda t: t[0]): over(img, l)
    return img

def mirror_face(px, x, y, w, h, dx, dy):
    for j in range(h):
        for i in range(w): px[dy + j][dx + i] = px[y + j][x + w - 1 - i]

def to_64(px32):
    """Legacy 64x32 -> 64x64: right leg (0,16) and right arm (40,16) are mirrored into the left leg (16,48) and left arm (32,48)."""
    px = [row[:] for row in px32] + [[(0, 0, 0, 0)] * 64 for _ in range(32)]
    def limb(sx, sy, dx, dy):  # 16x16 block: top (4,0) bottom (8,0) 4x4; right/front/left/back (0,4)(4,4)(8,4)(12,4) 4x12
        mirror_face(px, sx + 4, sy, 4, 4, dx + 4, dy)
        mirror_face(px, sx + 8, sy, 4, 4, dx + 8, dy)
        mirror_face(px, sx + 0, sy + 4, 4, 12, dx + 8, dy + 4)   # right face -> left face
        mirror_face(px, sx + 8, sy + 4, 4, 12, dx + 0, dy + 4)   # left face -> right face
        mirror_face(px, sx + 4, sy + 4, 4, 12, dx + 4, dy + 4)
        mirror_face(px, sx + 12, sy + 4, 4, 12, dx + 12, dy + 4)
    limb(0, 16, 16, 48); limb(40, 16, 32, 48)
    return px

def doll(px):
    """Front view paper doll (16x32) of a 64x64 skin."""
    out = [[(70, 70, 80, 255)] * 16 for _ in range(32)]
    def blit(sx, sy, w, h, dx, dy):
        for j in range(h):
            for i in range(w):
                s = px[sy + j][sx + i]
                if s[3]: out[dy + j][dx + i] = s[:3] + (255,)
    blit(8, 8, 8, 8, 4, 0); blit(20, 20, 8, 12, 4, 8); blit(44, 20, 4, 12, 0, 8); blit(36, 52, 4, 12, 12, 8)
    blit(4, 20, 4, 12, 4, 20); blit(20, 52, 4, 12, 8, 20)
    return out

def combos(kind):
    """A seeded random pick (COUNT[kind]) of every hair style/colour x top colour x bottom style/colour combination."""
    import random
    d = dyes()
    tops = TOPS[kind] or list(d)
    every = [(hs, h, t, bs, b) for hs in HAIR_STYLES[kind] for h in HAIR_OF[kind] for t in tops for bs in BOTTOM_STYLES for b in BOTTOMS[kind]]
    return sorted(random.Random(kind).sample(every, min(COUNT[kind], len(every))))

def name(kind, hs, h, t, bs, b): return 'populations_%s_%s_%s_%s_%s_%s.png' % (kind, hs.replace('_', ''), h, t, bs.replace('_', ''), b)

def generate():
    d = dyes(); os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if re.match(r'populations_(steve|alex)_.*\.png$', f): os.remove(os.path.join(OUT, f))
    n = 0
    for kind in ('steve', 'alex'):
        for c in combos(kind):
            hs, h, t, bs, b = c
            P.write(os.path.join(OUT, name(kind, *c)), 64, 64, to_64(compose(kind, hs, HAIR_COLORS[h], d[t], bs, d[b]))); n += 1
    print('wrote', n, 'skins to', OUT)

def preview(out, which):
    d = dyes(); kind = 'steve' if which == 'boy' else 'alex'
    import random; random.seed(3)
    picks = random.sample(combos(kind), 24)
    cols = 8; K = 6
    sheet = [[(30, 30, 36, 255)] * (18 * K * cols) for _ in range(34 * K * 3)]
    for i, (hs, h, t, bs, b) in enumerate(picks):
        dl = P.scaled(doll(to_64(compose(kind, hs, HAIR_COLORS[h], d[t], bs, d[b]))), K)
        ox, oy = (i % cols) * 18 * K + K, (i // cols) * 34 * K + K
        for y, row in enumerate(dl): sheet[oy + y][ox:ox + len(row)] = row
    P.write(out, 18 * K * cols, 34 * K * 3, sheet)

if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] == 'generate': generate()
    elif len(sys.argv) >= 3 and sys.argv[1] == 'preview': preview(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'girl')
    else: print(__doc__)
