'use strict';
// Minimal readers for .tar.gz and .zip (no dependencies). Entries: { name, data() }; only regular files are returned.
// Names are validated: no absolute paths, no "..", no backslashes; links are refused.
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

function cleanName(raw) {
  const n = raw.replace(/\/+$/, '');
  if (!n || n.startsWith('/') || n.includes('\\') || n.includes('\0') || n.split('/').some((p) => p === '..' || p === '')) throw new Error('Unsafe path in archive: ' + raw);
  return n;
}

function readTarGz(gz, maxBytes = 1 << 30) {
  const buf = zlib.gunzipSync(gz, { maxOutputLength: maxBytes });
  const out = [];
  let off = 0, longName = null, pax = {};
  const str = (a, b) => { const s = buf.toString('utf8', a, b); const z = s.indexOf('\0'); return z < 0 ? s : s.slice(0, z); };
  while (off + 512 <= buf.length) {
    if (buf.subarray(off, off + 512).every((v) => v === 0)) break; // end marker
    const size = parseInt(str(off + 124, off + 136).trim() || '0', 8);
    if (!Number.isFinite(size) || size < 0) throw new Error('Bad tar header');
    const type = String.fromCharCode(buf[off + 156] || 48);
    let name = str(off, off + 100);
    const prefix = str(off + 345, off + 500);
    if (prefix && str(off + 257, off + 262) === 'ustar') name = prefix + '/' + name;
    const dataStart = off + 512;
    const data = buf.subarray(dataStart, dataStart + size);
    if (data.length !== size) throw new Error('Truncated tar');
    if (type === 'x') { // pax extended header: "<len> key=value\n"
      pax = {};
      let p = 0;
      const t = data.toString('utf8');
      const b = Buffer.from(t, 'utf8');
      while (p < b.length) {
        const sp = b.indexOf(0x20, p); if (sp < 0) break;
        const len = parseInt(b.toString('utf8', p, sp), 10); if (!(len > 0)) break;
        const rec = b.toString('utf8', sp + 1, p + len - 1);
        const eq = rec.indexOf('=');
        if (eq > 0) pax[rec.slice(0, eq)] = rec.slice(eq + 1);
        p += len;
      }
    } else if (type === 'L') longName = data.toString('utf8').replace(/\0.*$/, '');
    else if (type === 'g') { /* global header: ignored */ }
    else {
      if (pax.path) name = pax.path; else if (longName) name = longName;
      pax = {}; longName = null;
      if (type === '0') out.push({ name: cleanName(name), data: () => data });
      else if (type === '5') { /* directory: implied by file paths */ }
      else throw new Error('Archive contains a link or special file: ' + name);
    }
    off = dataStart + Math.ceil(size / 512) * 512;
  }
  return out;
}

function readZip(buf, maxFileBytes = 1 << 29) {
  let e = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) if (buf.readUInt32LE(i) === 0x06054b50) { e = i; break; }
  if (e < 0) throw new Error('Not a zip file');
  const count = buf.readUInt16LE(e + 10);
  let p = buf.readUInt32LE(e + 16);
  if (count === 0xffff || p === 0xffffffff) throw new Error('Zip64 archives are not supported');
  const out = [];
  for (let i = 0; i < count; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('Bad zip directory');
    const c = p;
    const method = buf.readUInt16LE(p + 10), csize = buf.readUInt32LE(p + 20), usize = buf.readUInt32LE(p + 24);
    const nlen = buf.readUInt16LE(p + 28), elen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32), lo = buf.readUInt32LE(p + 42);
    const raw = buf.toString('utf8', p + 46, p + 46 + nlen);
    p += 46 + nlen + elen + clen;
    if (raw.endsWith('/')) continue; // directory
    const attr = buf.readUInt32LE(c + 38) >>> 16; // unix mode (symlink = 0120000)
    if ((attr & 0o170000) === 0o120000) throw new Error('Archive contains a link: ' + raw);
    if (usize > maxFileBytes) throw new Error('File too large in archive: ' + raw);
    const name = cleanName(raw);
    out.push({ name, data: () => {
      if (buf.readUInt32LE(lo) !== 0x04034b50) throw new Error('Bad zip entry');
      const start = lo + 30 + buf.readUInt16LE(lo + 26) + buf.readUInt16LE(lo + 28);
      const comp = buf.subarray(start, start + csize);
      if (method === 0) return comp;
      if (method === 8) return zlib.inflateRawSync(comp, { maxOutputLength: maxFileBytes });
      throw new Error('Unsupported zip compression in ' + name);
    } });
  }
  return out;
}

// Writes entries (already filtered/renamed by the caller: { rel, data }) under dest.
function writeEntries(dest, items) {
  const root = path.resolve(dest);
  for (const it of items) {
    const full = path.resolve(root, it.rel);
    if (!full.startsWith(root + path.sep)) throw new Error('Unsafe path: ' + it.rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, it.data());
  }
}

module.exports = { readTarGz, readZip, writeEntries, cleanName };
