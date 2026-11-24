'use strict';
// Draws assets/icon.png (512x512): a blocky isometric cube on a dark rounded square. No dependencies (writes the PNG itself).
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const N = 512, B = 16; // canvas size, block size (pixel-art look: everything is drawn in 16 px blocks)
const px = Buffer.alloc(N * N * 4); // RGBA, transparent

const inPoly = (poly, x, y) => {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
};
const cx = 256, cy = 256, R = 176;
const P = { top: [cx, cy - R], ur: [cx + R * 0.866, cy - R / 2], lr: [cx + R * 0.866, cy + R / 2], bot: [cx, cy + R], ll: [cx - R * 0.866, cy + R / 2], ul: [cx - R * 0.866, cy - R / 2], c: [cx, cy] };
const faces = {
  top: { poly: [P.top, P.ur, P.c, P.ul], color: [143, 230, 211] },
  left: { poly: [P.ul, P.c, P.bot, P.ll], color: [59, 157, 140] },
  right: { poly: [P.ur, P.lr, P.bot, P.c], color: [38, 112, 100] },
};
const hex = [P.top, P.ur, P.lr, P.bot, P.ll, P.ul];
const faceAt = (x, y) => { for (const k of Object.keys(faces)) if (inPoly(faces[k].poly, x, y)) return k; return null; };

const inRound = (x, y, r) => { // rounded square covering the canvas
  const dx = Math.max(r - x, 0, x - (N - 1 - r)), dy = Math.max(r - y, 0, y - (N - 1 - r));
  return dx * dx + dy * dy <= r * r;
};

function put(bx, by, rgb) {
  for (let y = by * B; y < by * B + B; y++) for (let x = bx * B; x < bx * B + B; x++) { const o = (y * N + x) * 4; px[o] = rgb[0]; px[o + 1] = rgb[1]; px[o + 2] = rgb[2]; px[o + 3] = 255; }
}
const blocks = N / B;
for (let by = 0; by < blocks; by++) for (let bx = 0; bx < blocks; bx++) {
  const x = bx * B + B / 2, y = by * B + B / 2;
  if (!inRound(x, y, 112)) continue;
  const edge = bx === 0 || by === 0 || bx === blocks - 1 || by === blocks - 1 || !inRound(x + B, y, 112) || !inRound(x - B, y, 112) || !inRound(x, y + B, 112) || !inRound(x, y - B, 112);
  put(bx, by, edge ? [34, 52, 84] : (by < blocks / 2 ? [16, 26, 44] : [11, 18, 32])); // dark background, a bit lighter at the top
}
for (let by = 0; by < blocks; by++) for (let bx = 0; bx < blocks; bx++) {
  const x = bx * B + B / 2, y = by * B + B / 2;
  const f = faceAt(x, y);
  if (!f) continue;
  const near = (dx, dy) => faceAt(x + dx * B, y + dy * B) === null && !inPoly(hex, x + dx * B, y + dy * B);
  if (near(1, 0) || near(-1, 0) || near(0, 1) || near(0, -1)) { put(bx, by, [8, 36, 32]); continue; } // outline
  let c = faces[f].color;
  // a few lighter "pixels" on the top face and darker ones on the sides (block texture)
  const h = ((bx * 73856093) ^ (by * 19349663)) & 15;
  if (h === 0) c = c.map((v) => Math.min(255, v + 28));
  else if (h === 1) c = c.map((v) => Math.max(0, v - 22));
  put(bx, by, c);
}

// PNG writer
const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
const crc = (buf) => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
const raw = Buffer.alloc((N * 4 + 1) * N);
for (let y = 0; y < N; y++) { raw[y * (N * 4 + 1)] = 0; px.copy(raw, y * (N * 4 + 1) + 1, y * N * 4, (y + 1) * N * 4); }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(N, 0); ihdr.writeUInt32BE(N, 4); ihdr[8] = 8; ihdr[9] = 6;
const out = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
const dst = path.join(__dirname, '..', 'assets', 'icon.png');
fs.writeFileSync(dst, out);
console.log('wrote', dst, out.length, 'bytes');
