// Reference implementation of the Bezpečné QR scoring rules (shared/rules/weights.json).
// BQCore (Swift) and the future Android engine must reproduce these numbers exactly for
// every sample in shared/testdata/samples.json.

const SCORED_ENGINES = new Set(['url', 'payment', 'sms', 'phone', 'generic']);

export function sigmoid(x) {
  return 1 / (1 + Math.exp(-x));
}

/**
 * @param {object} weights  parsed shared/rules/weights.json
 * @param {object} sample   one corpus sample ({ engine, signals, completeness })
 * @returns {{ scored: boolean, score: number|null, band: string, math: object }}
 */
export function assess(weights, sample) {
  const engine = sample.engine || 'none';
  const signals = sample.signals || [];

  if (!SCORED_ENGINES.has(engine) || (engine === 'generic' && signals.length === 0)) {
    return { scored: false, score: null, band: 'info', math: { note: 'decode-only / informational type' } };
  }

  const baseline = (weights.engines[engine] || weights.engines.generic).baseline;
  const byGroup = new Map();
  const floors = [];

  for (const s of signals) {
    const def = weights.signals[s.id];
    if (!def) throw new Error(`Unknown evidence signal: ${s.id}`);
    if (!byGroup.has(def.group)) byGroup.set(def.group, []);
    byGroup.get(def.group).push({ id: s.id, weight: def.weight });
    if (def.floor) floors.push({ id: s.id, floor: def.floor });
  }

  const groups = [];
  let sum = 0;
  for (const [group, items] of byGroup) {
    const g = weights.groups[group];
    if (!g) throw new Error(`Unknown group: ${group}`);
    const combined = g.combine === 'max' ? Math.max(...items.map((i) => i.weight)) : items.reduce((a, i) => a + i.weight, 0);
    const contribution = Math.min(g.cap, combined);
    sum += contribution;
    groups.push({ group, items, combined: round2(combined), cap: g.cap, contribution: round2(contribution) });
  }

  const logit = baseline + sum;
  let raw = 100 * sigmoid(logit);
  const math = { baseline, groups, logit: round2(logit), raw: round2(raw) };

  const weakOnly = groups.length > 0 && groups.every((g) => weights.weakOnlyCap.groups.includes(g.group));
  if (weakOnly && raw > weights.weakOnlyCap.cap) {
    raw = weights.weakOnlyCap.cap;
    math.weakOnlyCapApplied = weights.weakOnlyCap.cap;
  }

  let score = Math.round(raw);
  const maxFloor = floors.reduce((m, f) => Math.max(m, f.floor), 0);
  if (maxFloor > score) {
    score = maxFloor;
    math.floorApplied = floors.find((f) => f.floor === maxFloor);
  }

  let band = weights.bands.find((b) => score >= b.min && score <= b.max).id;
  const state = sample.completeness?.state;
  if ((state === 'incomplete' || state === 'skipped') && score < 25) band = 'incomplete';

  return { scored: true, score, band, math };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
