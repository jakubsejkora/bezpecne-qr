/* "Bodlík" — an original geometric hedgehog (concept from the Codex UX review).
   Calm, never panicking, never celebrating "safe!". Expressions: checking, safe, caution, danger, incomplete, info, alert. */
window.BQ = window.BQ || {};

BQ.mascot = function (state = 'info', size = 76) {
  const ink = 'var(--ink)';
  const spikes = [
    [22, 70, 14, 52, 32, 60], [30, 58, 26, 38, 44, 50], [42, 48, 44, 28, 58, 44], [56, 42, 62, 22, 70, 42],
    [68, 40, 78, 24, 80, 44], [18, 82, 4, 72, 22, 72],
  ].map(([a, b, c, d, e, f]) => `<path d="M${a} ${b} L${c} ${d} L${e} ${f}z" fill="${ink}"/>`).join('');

  const eyeOpen = `<circle cx="92" cy="60" r="4.2" fill="#10182b"/><circle cx="93.5" cy="58.5" r="1.4" fill="#fff"/>`;
  const eyeClosed = `<path d="M87.5 60.5 q4.5 4 9 0" stroke="#10182b" stroke-width="2.6" fill="none" stroke-linecap="round"/>`;
  const browCalm = '';
  const browFirm = `<path d="M86 52.5 l11 -2.5" stroke="#10182b" stroke-width="2.6" stroke-linecap="round"/>`;
  const browTilt = `<path d="M87 51 q5 -3 10 0" stroke="#10182b" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;

  let eyes = eyeOpen, brow = browCalm, extra = '', mouth = `<path d="M100 74 q-4 3 -8 1" stroke="#10182b" stroke-width="2" fill="none" stroke-linecap="round"/>`;
  let tilt = 0;

  if (state === 'checking') {
    extra = `<g class="m-glass"><circle cx="104" cy="64" r="15" fill="rgba(180,220,255,.35)" stroke="#334155" stroke-width="4"/><path d="M93 76 l-12 14" stroke="#334155" stroke-width="6" stroke-linecap="round"/></g>`;
  } else if (state === 'safe') {
    eyes = eyeClosed;
    mouth = `<path d="M101 73 q-5 5 -10 1" stroke="#10182b" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
  } else if (state === 'caution' || state === 'alert') {
    brow = browTilt;
    extra = `<g class="m-paw"><ellipse cx="70" cy="68" rx="7" ry="15" fill="#f4e3cf" transform="rotate(-18 70 68)"/><circle cx="66" cy="54" r="7.5" fill="#f4e3cf"/></g>`;
    mouth = `<path d="M100 76 h-8" stroke="#10182b" stroke-width="2.2" stroke-linecap="round"/>`;
  } else if (state === 'danger') {
    brow = browFirm;
    extra = `<g class="m-paw"><ellipse cx="68" cy="66" rx="8" ry="16" fill="#f4e3cf" transform="rotate(-10 68 66)"/><rect x="56" y="36" width="20" height="22" rx="9" fill="#f4e3cf"/><path d="M60 40 v8 M65 38 v10 M70 40 v8" stroke="#d9c2a6" stroke-width="2" stroke-linecap="round"/></g>`;
    mouth = `<path d="M100 77 q-4 -2 -8 0" stroke="#10182b" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
  } else if (state === 'incomplete') {
    tilt = -8;
    brow = browTilt;
    extra = `<g transform="translate(70 4)"><path d="M6 22 a8 8 0 0 1 3-15 a10 10 0 0 1 19 2 a7 7 0 0 1 1 13z" fill="#e2e8f0"/><text x="17" y="21" font-size="13" font-weight="800" text-anchor="middle" fill="#64748b" font-family="-apple-system, sans-serif">?</text></g>`;
  }

  return `<svg class="mascot" viewBox="0 0 124 110" width="${size}" height="${size}" role="img" aria-label="Bodlík">
    <g class="m-breathe" transform="rotate(${tilt} 62 70)">
      <ellipse cx="62" cy="100" rx="42" ry="5" fill="#000" opacity=".12"/>
      ${spikes}
      <path d="M14 94 C12 60 40 38 70 38 C96 38 112 56 112 78 C112 90 104 96 92 96 L14 96 Z" fill="${ink}"/>
      <path d="M76 52 C96 46 116 60 118 72 C114 84 98 88 80 86 C74 76 72 62 76 52 Z" fill="#f4e3cf"/>
      <circle cx="118" cy="72" r="5" fill="#10182b"/>
      <ellipse cx="96" cy="72" rx="4" ry="2.6" fill="#f9a8b8" opacity=".85"/>
      ${eyes}${brow}${mouth}
      <ellipse cx="34" cy="97" rx="10" ry="5" fill="#10182b" opacity=".85"/><ellipse cx="80" cy="97" rx="10" ry="5" fill="#10182b" opacity=".85"/>
      ${extra}
    </g>
  </svg>`;
};
