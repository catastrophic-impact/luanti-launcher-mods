"""Dump the texture-coordinate layout of a .b3d mesh: per mesh node, triangle count and UV bounding boxes (in pixels of a 64x64 texture)
grouped by connected face (quads). Usage: b3d_uv.py file.b3d [texture_size]"""
import struct, sys
data = open(sys.argv[1], 'rb').read(); TS = int(sys.argv[2]) if len(sys.argv) > 2 else 64
def chunks(buf, pos, end):
    while pos + 8 <= end:
        tag = buf[pos:pos+4].decode('latin1'); size = struct.unpack('<I', buf[pos+4:pos+8])[0]
        yield tag, pos + 8, pos + 8 + size
        pos += 8 + size
def cstr(buf, pos):
    e = buf.index(b'\0', pos); return buf[pos:e].decode('latin1'), e + 1
def walk(pos, end, depth, path):
    for tag, s, e in chunks(data, pos, end):
        if tag == 'NODE':
            name, p = cstr(data, s); p += 40
            walk(p, e, depth + 1, path + [name])
        elif tag == 'MESH':
            verts = []; tris = []
            for t2, s2, e2 in chunks(data, s + 4, e):
                if t2 == 'VRTS':
                    flags, nsets, sz = struct.unpack('<III', data[s2:s2+12]); p = s2 + 12
                    stride = 12 + (12 if flags & 1 else 0) + (16 if flags & 2 else 0) + 4 * nsets * sz
                    while p + stride <= e2:
                        q = p + 12 + (12 if flags & 1 else 0) + (16 if flags & 2 else 0)
                        u, v = struct.unpack('<ff', data[q:q+8]); xyz = struct.unpack('<fff', data[p:p+12])
                        verts.append((xyz, u * TS, v * TS)); p += stride
                elif t2 == 'TRIS':
                    p = s2 + 4
                    while p + 12 <= e2:
                        tris.append(struct.unpack('<III', data[p:p+12])); p += 12
            print('/'.join(path), 'verts', len(verts), 'tris', len(tris))
            # group triangles into faces by shared plane: report UV bbox of each pair of triangles
            for i in range(0, len(tris), 2):
                idx = [x for t in tris[i:i+2] for x in t]
                us = [verts[j][1] for j in idx]; vs = [verts[j][2] for j in idx]
                zs = [verts[j][0] for j in idx]
                print('   face', i // 2, 'uv x %.1f-%.1f y %.1f-%.1f' % (min(us), max(us), min(vs), max(vs)),
                      'xyz', ['%.2f..%.2f' % (min(c[k] for c in zs), max(c[k] for c in zs)) for k in range(3)])
        elif tag == 'BONE' or True:
            pass
walk(12, len(data), 0, [])
