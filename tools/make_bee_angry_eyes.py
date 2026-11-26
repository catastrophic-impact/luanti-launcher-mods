"""Make mods/bees/textures/bees_bee_features_angry.png from bees_bee_features.png: the eyes (dark blue-grey pixels and their white glints on the head faces) turn red.
Only the head columns x 8..24 are touched; the antenna tips (x<8) and the stinger (x>24) share a colour with the eyes and stay as they are.
Run:  python3 -I tools/make_bee_angry_eyes.py   (no PIL needed, uses tools/pnglib.py)"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import pnglib
src = os.path.join(here, '..', 'mods', 'bees', 'textures')
w, h, px = pnglib.read(os.path.join(src, 'bees_bee_features.png'))
MAP = {(48, 43, 55): (205, 28, 28), (30, 30, 40): (140, 12, 12), (253, 253, 253): (255, 150, 150), (226, 239, 245): (255, 185, 185)}
n = 0
for y in range(h):
    for x in range(8, 25):
        p = px[y][x]
        if p[3] and tuple(p[:3]) in MAP:
            px[y][x] = MAP[tuple(p[:3])] + (p[3],); n += 1
pnglib.write(os.path.join(src, 'bees_bee_features_angry.png'), w, h, px)
print('recoloured', n, 'pixels')
