"""Tiny PNG reader/writer (8-bit RGB/RGBA/palette, non-interlaced). No PIL on this machine."""
import zlib, struct

def read(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8; idat = b''; plte = None; trns = None
    while pos < len(d):
        n, t = struct.unpack('>I4s', d[pos:pos+8]); c = d[pos+8:pos+8+n]; pos += 12 + n
        if t == b'IHDR': w, h, bd, ct, _, _, il = struct.unpack('>IIBBBBB', c); assert il == 0 and (bd == 8 or (ct == 3 and bd in (1, 2, 4)))
        elif t == b'PLTE': plte = c
        elif t == b'tRNS': trns = c
        elif t == b'IDAT': idat += c
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(idat); stride = (w * bd + 7) // 8 if ct == 3 else w * ch; rows = []; prev = bytearray(stride); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p+1:p+1+stride]); p += 1 + stride
        for i in range(stride):
            a = line[i-ch] if i >= ch else 0; b = prev[i]; c2 = prev[i-ch] if i >= ch else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c2), abs(a - c2), abs(a + b - 2*c2)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c2)
                line[i] = (line[i] + pr) & 255
        rows.append(line); prev = line
    px = []
    for line in rows:
        r = []
        for x in range(w):
            if ct == 6: r.append(tuple(line[x*4:x*4+4]))
            elif ct == 2: r.append(tuple(line[x*3:x*3+3]) + (255,))
            elif ct == 3:
                i = line[x] if bd == 8 else (line[x * bd // 8] >> (8 - bd - (x * bd) % 8)) & ((1 << bd) - 1); a = trns[i] if trns and i < len(trns) else 255
                r.append((plte[i*3], plte[i*3+1], plte[i*3+2], a))
            elif ct == 4: r.append((line[x*2],) * 3 + (line[x*2+1],))
            else: r.append((line[x],) * 3 + (255,))
        px.append(r)
    return w, h, px

def write(path, w, h, px):
    raw = b''.join(b'\x00' + bytes(v for p in row for v in p) for row in px)
    def chunk(t, c): return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def scaled(px, k):
    return [[p for p in row for _ in range(k)] for row in px for _ in range(k)]

def checker(px, bg=((90, 90, 90, 255), (140, 140, 140, 255))):
    """Composite over a grey checkerboard so transparency is visible."""
    out = []
    for y, row in enumerate(px):
        r = []
        for x, p in enumerate(row):
            b = bg[((x // 4) + (y // 4)) % 2]; a = p[3] / 255
            r.append(tuple(int(p[i] * a + b[i] * (1 - a)) for i in range(3)) + (255,))
        out.append(r)
    return out
