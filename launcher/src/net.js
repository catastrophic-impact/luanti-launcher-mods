'use strict';
// HTTPS GET with redirects, a size cap and a timeout. Only ever called after an explicit button press in the UI.
const https = require('https');
const nodeNet = require('net');

// Node's default 250 ms per-address connect attempt is too short for some links (IPv6 unreachable + slow IPv4 gave ETIMEDOUT).
try { nodeNet.setDefaultAutoSelectFamilyAttemptTimeout(5000); } catch { /* older runtime */ }

function buffer(url, { maxBytes = 400 * 1024 * 1024, timeoutMs = 60000, redirects = 5, accept } = {}) {
  return new Promise((resolve, reject) => {
    let u;
    try { u = new URL(url); } catch { return reject(new Error('Bad URL')); }
    if (u.protocol !== 'https:') return reject(new Error('Only https downloads are allowed'));
    const req = https.get(u, { headers: { 'User-Agent': 'luanti-launcher', ...(accept ? { Accept: accept } : {}) }, timeout: timeoutMs }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        if (redirects <= 0) return reject(new Error('Too many redirects'));
        return resolve(buffer(new URL(res.headers.location, u).toString(), { maxBytes, timeoutMs, redirects: redirects - 1, accept }));
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`${u.host}: HTTP ${res.statusCode}`)); }
      const chunks = []; let n = 0;
      res.on('data', (c) => { n += c.length; if (n > maxBytes) { req.destroy(new Error('Download is too large')); } else chunks.push(c); });
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    });
    req.on('timeout', () => req.destroy(new Error('Network timeout')));
    req.on('error', (e) => reject(new Error('Network error: ' + (e.message || (e.errors && e.errors.map((x) => x.code).join(', ')) || e.code || 'unknown'))));
  });
}
const json = async (url, opts) => JSON.parse((await buffer(url, { maxBytes: 20 * 1024 * 1024, accept: 'application/json', ...opts })).toString('utf8'));

module.exports = { buffer, json };
