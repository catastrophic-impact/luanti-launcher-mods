"""Widen the 3px arms of slim (alex) skins to the 4px layout of the mesh. Usage: slim_to_wide.py SRC_DIR DST_DIR"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import pnglib as P
src, dst = sys.argv[1:3]
def widen(px, ox, oy):
    # (start_x, slim_w) of each face block in the arm's 16x16 area; rows: top/bottom oy..oy+4, sides oy+4..oy+16
    old = [r[:] for r in px]
    def put(rows, sx, sw, dx):  # stretch sw columns at sx to sw+1 columns at dx (duplicate the middle column)
        cols = list(range(sw)); cols.insert(sw // 2, sw // 2)
        for y in rows:
            for i, c in enumerate(cols): px[y][dx + i] = old[y][sx + c]
    top = range(oy, oy + 4); side = range(oy + 4, oy + 16)
    put(top, ox + 4, 3, ox + 4); put(top, ox + 7, 3, ox + 8)
    put(side, ox + 4, 3, ox + 4)
    for y in side:
        for i in range(4): px[y][ox + 8 + i] = old[y][ox + 7 + i]   # inner side (4 wide, shifted)
    put(side, ox + 11, 3, ox + 12)
for f in sorted(os.listdir(src)):
    if not f.endswith('.png') or f.endswith('_base.png'): continue
    w, h, px = P.read(os.path.join(src, f))
    for ox, oy in ((40, 16), (32, 48), (40, 32), (48, 48)): widen(px, ox, oy)
    P.write(os.path.join(dst, 'populations_' + f), w, h, px)
