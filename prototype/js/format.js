/* Formatting helpers (mirror what BQUI will do natively). */
window.BQ = window.BQ || {};

BQ.esc = function (s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
};

BQ.fmt = {
  /** 1234.5 → "1 234,50" (cs) / "1,234.50" (en) */
  amount(value, currency) {
    if (value === null || value === undefined || value === '') return null;
    const n = Number(value);
    if (!Number.isFinite(n)) return null;
    const locale = BQ.lang === 'cs' ? 'cs-CZ' : 'en-GB';
    const decimals = currency === 'BTC' ? 4 : 2;
    const num = n.toLocaleString(locale, { minimumFractionDigits: n % 1 === 0 && currency !== 'BTC' ? 0 : decimals, maximumFractionDigits: currency === 'BTC' ? 8 : 2 });
    const sym = { CZK: 'Kč', EUR: '€', CHF: 'CHF', BTC: 'BTC', USDT: 'USDT' }[currency] || currency || '';
    return { num, sym };
  },
  iban(iban) { return String(iban || '').replace(/\s+/g, '').replace(/(.{4})/g, '$1 ').trim(); },
  date(iso) {
    if (!iso) return '';
    const d = new Date(iso.length === 10 ? iso + 'T12:00:00' : iso);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleDateString(BQ.lang === 'cs' ? 'cs-CZ' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
  },
  dateTime(iso) {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleString(BQ.lang === 'cs' ? 'cs-CZ' : 'en-GB', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  },
  time(iso) {
    const d = new Date(iso);
    return d.toLocaleTimeString(BQ.lang === 'cs' ? 'cs-CZ' : 'en-GB', { hour: '2-digit', minute: '2-digit' });
  },
  /** Emphasise the registrable domain inside a host. */
  hostHTML(host, registrable) {
    const h = BQ.esc(host || '');
    if (!registrable || !host || !host.endsWith(registrable)) return `<b>${h}</b>`;
    const prefix = host.slice(0, host.length - registrable.length);
    return `${BQ.esc(prefix)}<b>${BQ.esc(registrable)}</b>`;
  },
  /** Fill {placeholders} from args (args may contain {cs,en} objects). */
  fill(template, args = {}) {
    return String(template ?? '').replace(/\{(\w+)\}/g, (_, k) => (args[k] !== undefined ? BQ.esc(BQ.pick(args[k])) : `{${k}}`));
  },
  initials(name) {
    return String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join('');
  },
  hue(str) {
    let h = 0;
    for (const ch of String(str)) h = (h * 31 + ch.charCodeAt(0)) % 360;
    return h;
  },
};

/** Texts for a signal/consequence/check from signals.json */
BQ.sig = {
  evidence(id, args) {
    const e = window.BQ_DATA.signals.evidence[id];
    if (!e) return { title: id, observation: '', implication: '', action: '' };
    const t = e[BQ.lang] || e.cs;
    return { title: BQ.fmt.fill(t.title, args), observation: BQ.fmt.fill(t.observation, args), implication: BQ.fmt.fill(t.implication, args), action: BQ.fmt.fill(t.action, args) };
  },
  consequence(id, args) {
    const c = window.BQ_DATA.signals.consequences[id];
    if (!c) return { title: id, text: '', severity: 'info' };
    const t = c[BQ.lang] || c.cs;
    return { title: BQ.fmt.fill(t.title, args), text: BQ.fmt.fill(t.text, args), severity: c.severity };
  },
  check(id, args) {
    const c = window.BQ_DATA.signals.checks[id];
    return c ? BQ.fmt.fill(c[BQ.lang] || c.cs, args) : id;
  },
  incomplete(id) {
    const c = window.BQ_DATA.signals.incomplete[id];
    return c ? (c[BQ.lang] || c.cs) : BQ.esc(id || '');
  },
};
