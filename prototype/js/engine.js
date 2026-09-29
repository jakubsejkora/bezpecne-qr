/* In-browser copy of scripts/lib/engine.mjs, plus "what if" transforms for the network toggles.
   The generator already validated every sample; this lets the prototype recompute live when
   you switch to Offline or turn internet checks off. */
window.BQ = window.BQ || {};

BQ.engine = (function () {
  const SCORED = new Set(['url', 'payment', 'sms', 'phone', 'generic']);
  const sigmoid = (x) => 1 / (1 + Math.exp(-x));
  const r2 = (n) => Math.round(n * 100) / 100;

  function assess(sample) {
    const W = window.BQ_DATA.weights;
    const engine = sample.engine || 'none';
    const signals = sample.signals || [];
    if (!SCORED.has(engine) || (engine === 'generic' && signals.length === 0)) {
      return { scored: false, score: null, band: 'info', math: { note: 'decode-only / informational' } };
    }
    const baseline = (W.engines[engine] || W.engines.generic).baseline;
    const byGroup = new Map();
    const floors = [];
    for (const s of signals) {
      const def = W.signals[s.id];
      if (!def) continue;
      if (!byGroup.has(def.group)) byGroup.set(def.group, []);
      byGroup.get(def.group).push({ id: s.id, weight: def.weight });
      if (def.floor) floors.push({ id: s.id, floor: def.floor });
    }
    const groups = [];
    let sum = 0;
    for (const [group, items] of byGroup) {
      const g = W.groups[group];
      const combined = g.combine === 'max' ? Math.max(...items.map((i) => i.weight)) : items.reduce((a, i) => a + i.weight, 0);
      const contribution = Math.min(g.cap, combined);
      sum += contribution;
      groups.push({ group, items, combined: r2(combined), cap: g.cap, contribution: r2(contribution) });
    }
    const logit = baseline + sum;
    let raw = 100 * sigmoid(logit);
    const math = { baseline, groups, logit: r2(logit), raw: r2(raw) };
    const weakOnly = groups.length > 0 && groups.every((g) => W.weakOnlyCap.groups.includes(g.group));
    if (weakOnly && raw > W.weakOnlyCap.cap) { raw = W.weakOnlyCap.cap; math.weakOnlyCapApplied = W.weakOnlyCap.cap; }
    let score = Math.round(raw);
    const maxFloor = floors.reduce((m, f) => Math.max(m, f.floor), 0);
    if (maxFloor > score) { score = maxFloor; math.floorApplied = floors.find((f) => f.floor === maxFloor); }
    let band = W.bands.find((b) => score >= b.min && score <= b.max).id;
    const state = sample.completeness?.state;
    if ((state === 'incomplete' || state === 'skipped') && score < 25) band = 'incomplete';
    return { scored: true, score, band, math };
  }

  const NETWORK_EVIDENCE = /^(page\.|intel\.|url\.domain\.|url\.identity\.false_official)/;
  const PAGE_CHECKS = new Set(['chk.page_extract', 'chk.redirects', 'chk.https_ok', 'chk.shortener_resolved', 'chk.https_upgraded']);
  const DOMAIN_CHECKS = new Set(['chk.quad9_ok', 'chk.domain_age']);

  /** Apply the network toggles (offline / checks off) to a URL-like sample. */
  function applyNetwork(sample, { network, pageFetch, domainChecks }) {
    const urlLike = sample.engine === 'url' && sample.inspection && sample.completeness?.state === 'complete';
    const pageOff = network === 'offline' || !pageFetch;
    const domainOff = network === 'offline' || !domainChecks;
    if (!urlLike || (!pageOff && !domainOff)) return { ...sample, assessment: sample.assessment || assess(sample) };
    const s = JSON.parse(JSON.stringify(sample));
    if (pageOff) {
      s.signals = s.signals.filter((x) => !/^(page\.|url\.identity\.false_official)/.test(x.id));
      s.checks = (s.checks || []).filter((c) => !PAGE_CHECKS.has(c.id));
      s.consequences = (s.consequences || []).filter((c) => !['csq.subscription_charge', 'csq.billing_gateway'].includes(c.id));
      s.inspection = { ...s.inspection, chain: [], final: null, page: null };
      s.completeness = { state: 'incomplete', reason: network === 'offline' ? 'inc.offline' : 'inc.checks_disabled' };
    }
    if (domainOff) {
      s.signals = s.signals.filter((x) => !/^(intel\.|url\.domain\.)/.test(x.id));
      s.checks = (s.checks || []).filter((c) => !DOMAIN_CHECKS.has(c.id));
      if (s.inspection) s.inspection = { ...s.inspection, domain: null };
    }
    s.whatIf = true;
    s.assessment = assess(s);
    return s;
  }

  return { assess, applyNetwork, NETWORK_EVIDENCE };
})();
