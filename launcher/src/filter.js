'use strict';
// ContentDB content filter (always on, no setting, no way to switch it off). Packages whose name, title, short description or tags
// match one of these whole words/phrases are never listed and never installed. This list is the whole filter: edit it here.
const BLOCKED = [
  // sexual or gender-ideology themes (not for children)
  'pride', 'lgbt', 'lgbtq', 'lgbtqia', 'lgbtq+', 'gay', 'lesbian', 'bisexual', 'pansexual', 'asexual', 'transgender', 'transsexual',
  'queer', 'nonbinary', 'non-binary', 'genderfluid', 'gender identity', 'gender fluid', 'drag queen', 'rainbow flag', 'trans flag',
  // sexual content
  'sex', 'sexual', 'sexy', 'nsfw', 'porn', 'porno', 'erotic', 'hentai', 'lewd', 'fetish', 'nude', 'nudity', 'naked', 'adult content', '18+',
];
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// Whole-word match (so "transport" or "essex" never match "trans"/"sex"); underscores and dashes separate words in package names.
const RE = new RegExp('(^|[^a-z0-9])(' + BLOCKED.map(esc).join('|') + ')(?![a-z0-9])', 'i');

// p: { name, title, description, tags: [] }; returns the matched word or '' when the package is fine.
function blockedBy(p) {
  const text = [p.name, p.title, p.description, ...(p.tags || [])].filter(Boolean).join(' \n ').replace(/_/g, ' ');
  const m = RE.exec(text);
  return m ? m[2].toLowerCase() : '';
}

module.exports = { BLOCKED, blockedBy };
