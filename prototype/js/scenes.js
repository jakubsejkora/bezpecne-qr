/* Illustrated "camera" scenes. Each embeds the sample's real code and returns its screen rect,
   so the scanner reticle can snap onto it. Everything is drawn locally — nothing is loaded. */
window.BQ = window.BQ || {};

BQ.scenes = (function () {
  const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, sans-serif';
  let uid = 0;

  function img(code, x, y, w, h) {
    return `<image href="${code.url}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="none" style="image-rendering:pixelated"/>`;
  }
  function codeBox(code, cx, cy, size) {
    const ratio = code.w / code.h;
    let w = size, h = size;
    if (ratio > 1.15) { w = Math.min(size * 1.9, size * ratio); h = w / ratio; }
    else if (ratio < 0.87) { h = size; w = size * ratio; }
    return { x: cx - w / 2, y: cy - h / 2, w, h };
  }
  function text(x, y, s, size, { weight = 600, fill = '#111', anchor = 'middle', ls = 0, opacity = 1, italic = false } = {}) {
    return `<text x="${x}" y="${y}" font-family='${FONT}' font-size="${size}" font-weight="${weight}" fill="${fill}" text-anchor="${anchor}" letter-spacing="${ls}" opacity="${opacity}" ${italic ? 'font-style="italic"' : ''}>${BQ.esc(s)}</text>`;
  }
  function bokeh(W, H, n, colors, seed) {
    let out = '';
    let r = seed;
    const rnd = () => ((r = (r * 9301 + 49297) % 233280) / 233280);
    for (let i = 0; i < n; i++) {
      const c = colors[i % colors.length];
      out += `<circle cx="${(rnd() * W).toFixed(1)}" cy="${(rnd() * H * 0.62).toFixed(1)}" r="${(12 + rnd() * 46).toFixed(1)}" fill="${c}" opacity="${(0.12 + rnd() * 0.35).toFixed(2)}"/>`;
    }
    return out;
  }
  function shadowFilter(id, dy = 12, sd = 14, op = 0.35) {
    return `<filter id="${id}" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="${dy}" stdDeviation="${sd}" flood-color="#000" flood-opacity="${op}"/></filter>`;
  }

  const SCENES = {
    cafe(W, H, code, s) {
      const id = `c${uid++}`;
      const cx = W / 2, cy = H * 0.42, size = W * 0.36;
      const b = codeBox(code, cx, cy + 8, size);
      const cardW = size + 70, cardH = size + 160;
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#24170f"/><stop offset=".55" stop-color="#4f3322"/><stop offset="1" stop-color="#6d4a31"/></linearGradient>
          <linearGradient id="${id}tb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b98555"/><stop offset="1" stop-color="#7a5230"/></linearGradient>
          <filter id="${id}bl"><feGaussianBlur stdDeviation="7"/></filter>${shadowFilter(id + 'sh')}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}bg)"/>
        <g filter="url(#${id}bl)">${bokeh(W, H, 22, ['#ffd88a', '#fff1c9', '#ffb86b', '#ffffff'], 7)}
          <rect x="${W * 0.62}" y="${H * 0.04}" width="${W * 0.5}" height="${H * 0.34}" fill="#ffe9c4" opacity=".35"/></g>
        <path d="M0 ${H * 0.64} L${W} ${H * 0.6} L${W} ${H} L0 ${H}z" fill="url(#${id}tb)"/>
        ${[0.7, 0.76, 0.83, 0.9, 0.96].map((y, i) => `<path d="M0 ${H * y} Q${W * 0.5} ${H * y - 10 + i * 3} ${W} ${H * y - 16}" stroke="#5e3d22" stroke-width="1.4" opacity=".35" fill="none"/>`).join('')}
        <g transform="translate(${W * 0.14} ${H * 0.61})"><rect x="-18" y="-10" width="46" height="46" rx="8" fill="#d9d2c5"/><ellipse cx="-2" cy="-26" rx="22" ry="12" fill="#5c9b4c" transform="rotate(-30)"/><ellipse cx="14" cy="-34" rx="20" ry="11" fill="#6fb35c" transform="rotate(25 14 -34)"/><ellipse cx="4" cy="-48" rx="16" ry="9" fill="#4f8b41"/></g>
        <g filter="url(#${id}sh)">
          <path d="M${cx - cardW / 2} ${cy - cardH / 2 + 10} L${cx + cardW / 2} ${cy - cardH / 2 + 10} L${cx + cardW / 2 + 8} ${cy + cardH / 2} L${cx - cardW / 2 - 8} ${cy + cardH / 2}z" fill="#fbfaf6"/>
        </g>
        ${text(cx, cy - cardH / 2 + 40, 'NÁŠ', 13, { weight: 700, ls: 3, fill: '#3b2f25' })}
        ${text(cx, cy - cardH / 2 + 60, 'JÍDELNÍ LÍSTEK', 15, { weight: 800, ls: 2, fill: '#3b2f25' })}
        ${img(code, b.x, b.y, b.w, b.h)}
        ${text(cx, cy + cardH / 2 - 28, 'Naskenujte pro zobrazení menu', 11.5, { weight: 500, fill: '#6b5b4b' })}
        <g transform="translate(${W * 0.83} ${H * 0.66})"><ellipse cx="0" cy="34" rx="46" ry="11" fill="#e9e4dc"/><path d="M-30 -10 h60 l-6 44 a8 8 0 0 1 -8 7 h-32 a8 8 0 0 1 -8 -7z" fill="#f4f1ec"/><ellipse cx="0" cy="-10" rx="30" ry="8" fill="#6a4128"/><path d="M29 0 q20 2 14 20 q-6 12 -18 8" stroke="#f4f1ec" stroke-width="7" fill="none"/></g>`,
      };
    },

    parking(W, H, code, s, sample) {
      const id = `p${uid++}`;
      const sticker = /fake|foreign|90206|sms-parking/.test(sample?.id || '');
      const two = sample === 'two';
      const cx = W / 2 - (two ? 18 : 0), cy = H * 0.44, size = W * 0.34;
      const bodyW = size + 96, bodyX = cx - bodyW / 2 + (two ? 18 : 0), bodyY = cy - size / 2 - 150, bodyH = size + 330;
      const b = codeBox(code, cx, cy, size);
      const rects = [b];
      let official = '';
      if (two && s.second) {
        const sz = size * 0.42;
        const ox = bodyX + bodyW - sz / 2 - 14, oy = cy + size / 2 + 88;
        const ob = codeBox(s.second, ox, oy, sz);
        rects.push(ob);
        official = `<rect x="${ob.x - 8}" y="${ob.y - 22}" width="${ob.w + 16}" height="${ob.h + 30}" rx="6" fill="#fff"/>${text(ox, ob.y - 8, 'parking.praha.eu', 8.5, { weight: 700, fill: '#1d4ed8' })}${img(s.second, ob.x, ob.y, ob.w, ob.h)}`;
      }
      const front = sticker || two
        ? `<g transform="rotate(-2 ${cx} ${cy})"><rect x="${b.x - 16}" y="${b.y - 46}" width="${b.w + 32}" height="${b.h + 70}" rx="14" fill="#ff4f9a"/>
            ${text(cx, b.y - 20, 'Scan & Pay', 17, { weight: 800, fill: '#fff' })}<rect x="${b.x - 4}" y="${b.y - 4}" width="${b.w + 8}" height="${b.h + 8}" rx="6" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}</g>`
        : `<rect x="${b.x - 14}" y="${b.y - 40}" width="${b.w + 28}" height="${b.h + 62}" rx="8" fill="#fff"/>${text(cx, b.y - 20, 'Zaplaťte online', 13, { weight: 700, fill: '#1d4ed8' })}${img(code, b.x, b.y, b.w, b.h)}${text(cx, b.y + b.h + 16, 'parking.praha.eu', 10.5, { weight: 700, fill: '#1d4ed8' })}`;
      return {
        rects,
        svg: `<defs>
          <linearGradient id="${id}sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8fb9df"/><stop offset=".5" stop-color="#dbe7f2"/><stop offset=".51" stop-color="#9aa3ad"/><stop offset="1" stop-color="#6d747d"/></linearGradient>
          <linearGradient id="${id}m" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2e343d"/><stop offset=".5" stop-color="#4a525e"/><stop offset="1" stop-color="#2a3038"/></linearGradient>
          <filter id="${id}bl"><feGaussianBlur stdDeviation="3.5"/></filter>${shadowFilter(id + 'sh', 14, 16, 0.4)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}sky)"/>
        <g filter="url(#${id}bl)" opacity=".9">
          <rect x="-10" y="${H * 0.12}" width="${W * 0.36}" height="${H * 0.4}" fill="#c9b7a3"/><rect x="${W * 0.3}" y="${H * 0.06}" width="${W * 0.34}" height="${H * 0.46}" fill="#e5d8c4"/><rect x="${W * 0.62}" y="${H * 0.15}" width="${W * 0.42}" height="${H * 0.37}" fill="#b9a893"/>
          ${Array.from({ length: 18 }, (_, i) => `<rect x="${(i % 6) * W * 0.17 + 10}" y="${H * 0.18 + Math.floor(i / 6) * 52}" width="${W * 0.07}" height="30" fill="#6c7f94" opacity=".55"/>`).join('')}
          <rect x="-20" y="${H * 0.47}" width="${W * 0.5}" height="${H * 0.08}" rx="30" fill="#2d6cdf" opacity=".85"/><rect x="${W * 0.55}" y="${H * 0.48}" width="${W * 0.55}" height="${H * 0.07}" rx="28" fill="#b91c1c" opacity=".8"/>
        </g>
        <rect x="${W / 2 - 14 + (two ? 0 : 0)}" y="${bodyY + bodyH - 20}" width="28" height="${H - bodyY - bodyH + 20}" fill="#2a2f36"/>
        <g filter="url(#${id}sh)"><rect x="${bodyX}" y="${bodyY}" width="${bodyW}" height="${bodyH}" rx="22" fill="url(#${id}m)"/></g>
        ${text(bodyX + bodyW / 2, bodyY + 30, 'PARKOVACÍ AUTOMAT', 12.5, { weight: 800, fill: '#e5e7eb', ls: 1.5 })}
        <rect x="${bodyX + 26}" y="${bodyY + 44}" width="${bodyW - 52}" height="46" rx="8" fill="#10261a"/>
        ${text(bodyX + bodyW / 2, bodyY + 73, 'P1 · ZÓNA MODRÁ · 40 Kč/h', 12, { weight: 700, fill: '#5ef08a' })}
        ${front}
        ${sticker ? text(bodyX + bodyW / 2, bodyY + bodyH - 58, 'Zaplaťte parkovné online:', 10.5, { weight: 600, fill: '#cbd5e1' }) + text(bodyX + bodyW / 2, bodyY + bodyH - 42, 'parking.praha.eu', 11.5, { weight: 800, fill: '#e2e8f0' }) : ''}
        ${official}
        ${Array.from({ length: 6 }, (_, i) => `<circle cx="${bodyX + 40 + (i % 3) * 22}" cy="${bodyY + bodyH - 104 + Math.floor(i / 3) * 22}" r="7" fill="#1f242b"/>`).join('')}
        <rect x="${bodyX + bodyW - 70}" y="${bodyY + bodyH - 112}" width="34" height="8" rx="4" fill="#15191e"/>`,
      };
    },

    bench(W, H, code) {
      const id = `b${uid++}`;
      const cx = W / 2, cy = H * 0.43, size = W * 0.34;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9ed3f5"/><stop offset=".55" stop-color="#e8f6ff"/></linearGradient>
          <linearGradient id="${id}g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8bc670"/><stop offset="1" stop-color="#4f8f3c"/></linearGradient>
          <linearGradient id="${id}post" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#1f2937"/><stop offset=".5" stop-color="#4b5563"/><stop offset="1" stop-color="#1f2937"/></linearGradient>
          <filter id="${id}bl"><feGaussianBlur stdDeviation="4"/></filter>${shadowFilter(id + 'sh', 8, 8, 0.3)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}sky)"/>
        <g filter="url(#${id}bl)">
          <circle cx="${W * 0.1}" cy="${H * 0.36}" r="90" fill="#5e9e4a"/><circle cx="${W * 0.28}" cy="${H * 0.3}" r="70" fill="#76b55e"/><circle cx="${W * 0.86}" cy="${H * 0.33}" r="100" fill="#5a9446"/><circle cx="${W * 0.68}" cy="${H * 0.38}" r="60" fill="#86c46b"/>
          <rect x="0" y="${H * 0.52}" width="${W}" height="${H * 0.48}" fill="url(#${id}g)"/>
          <path d="M${W * 0.2} ${H} Q${W * 0.45} ${H * 0.7} ${W * 0.5} ${H * 0.52} L${W * 0.58} ${H * 0.52} Q${W * 0.6} ${H * 0.7} ${W * 0.9} ${H}z" fill="#d8c7a4"/>
          <g transform="translate(${W * 0.06} ${H * 0.62})"><rect width="${W * 0.34}" height="12" rx="4" fill="#8a5a32"/><rect y="20" width="${W * 0.34}" height="12" rx="4" fill="#8a5a32"/><rect x="10" y="30" width="8" height="40" fill="#333"/><rect x="${W * 0.34 - 18}" y="30" width="8" height="40" fill="#333"/></g>
        </g>
        <rect x="${cx - 16}" y="0" width="32" height="${H}" fill="url(#${id}post)"/>
        <g filter="url(#${id}sh)" transform="rotate(3 ${cx} ${cy})">
          <rect x="${b.x - 16}" y="${b.y - 66}" width="${b.w + 32}" height="${b.h + 110}" rx="10" fill="#ffd60a"/>
          ${text(cx, b.y - 40, 'VYHRAJ', 17, { weight: 900, fill: '#111' })}${text(cx, b.y - 16, 'iPHONE 17 ZDARMA', 15, { weight: 900, fill: '#d61f69' })}
          <rect x="${b.x - 4}" y="${b.y - 4}" width="${b.w + 8}" height="${b.h + 8}" rx="4" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}
          ${text(cx, b.y + b.h + 26, 'Stačí naskenovat!', 13, { weight: 800, fill: '#111' })}
        </g>`,
      };
    },

    mall(W, H, code) {
      const id = `m${uid++}`;
      const cx = W / 2, cy = H * 0.44, size = W * 0.33;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3efe8"/><stop offset=".6" stop-color="#ded7cc"/><stop offset="1" stop-color="#b9b0a3"/></linearGradient>
          <linearGradient id="${id}p" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#d7d7d7"/><stop offset=".45" stop-color="#fafafa"/><stop offset="1" stop-color="#cfcfcf"/></linearGradient>
          <filter id="${id}bl"><feGaussianBlur stdDeviation="5"/></filter>${shadowFilter(id + 'sh', 6, 6, 0.25)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}bg)"/>
        <g filter="url(#${id}bl)">${bokeh(W, H, 14, ['#fff7d6', '#ffffff', '#ffe0b3'], 3)}
          <rect x="0" y="${H * 0.14}" width="${W * 0.26}" height="${H * 0.3}" fill="#2f5d8a" opacity=".55"/><rect x="${W * 0.74}" y="${H * 0.12}" width="${W * 0.3}" height="${H * 0.32}" fill="#b0413e" opacity=".5"/>
          ${text(W * 0.12, H * 0.13, 'SHOP', 22, { weight: 800, fill: '#2f5d8a' })}</g>
        <rect x="${cx - size / 2 - 60}" y="0" width="${size + 120}" height="${H}" fill="url(#${id}p)"/>
        <g filter="url(#${id}sh)" transform="rotate(-4 ${cx} ${cy})">
          <rect x="${b.x - 14}" y="${b.y - 52}" width="${b.w + 28}" height="${b.h + 84}" rx="12" fill="#1d4ed8"/>
          ${text(cx, b.y - 22, 'FREE Wi‑Fi & SLEVY', 15, { weight: 900, fill: '#fff' })}
          <rect x="${b.x - 4}" y="${b.y - 4}" width="${b.w + 8}" height="${b.h + 8}" rx="5" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}
          ${text(cx, b.y + b.h + 20, 'naskenuj mě', 12, { weight: 700, fill: '#dbeafe' })}
        </g>`,
      };
    },

    letter(W, H, code, s, sample) {
      const id = `l${uid++}`;
      const invoice = sample && /spd|sid|epc|swiss|paybysquare|invoice/.test(sample.id + sample.type);
      const pw = W * 0.84, ph = H * 0.62, px = (W - pw) / 2, py = H * 0.13;
      const wide = code.w / code.h > 1.15;
      const size = wide ? pw * 0.42 : W * 0.3;
      const cx = wide ? px + pw / 2 : px + pw - size / 2 - 26, cy = py + ph - (wide ? 70 : size / 2 + 40);
      const b = codeBox(code, cx, cy, size);
      const title = invoice ? 'FAKTURA č. FV2026-0815' : 'OZNÁMENÍ';
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}d" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e4d2b6"/><stop offset="1" stop-color="#c9ad86"/></linearGradient>
          ${shadowFilter(id + 'sh', 10, 12, 0.28)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}d)"/>
        ${[0.2, 0.4, 0.6, 0.8].map((y) => `<path d="M0 ${H * y} Q${W / 2} ${H * y + 18} ${W} ${H * y - 6}" stroke="#a88b63" stroke-width="1.2" fill="none" opacity=".35"/>`).join('')}
        <g filter="url(#${id}sh)" transform="rotate(-1.5 ${W / 2} ${H / 2})">
          <rect x="${px}" y="${py}" width="${pw}" height="${ph}" rx="4" fill="#fffefb"/>
          ${text(px + 24, py + 42, title, 16, { weight: 800, anchor: 'start', fill: '#111827' })}
          ${[0, 1, 2, 3, 4, 5, 6].map((i) => `<rect x="${px + 24}" y="${py + 68 + i * 22}" width="${(pw - 48) * (i % 3 === 2 ? 0.55 : 0.92)}" height="7" rx="3.5" fill="#d7dbe2"/>`).join('')}
          ${invoice ? `<rect x="${px + 24}" y="${py + 240}" width="${pw - 48}" height="1.5" fill="#e5e7eb"/>${text(px + 24, py + 268, 'K úhradě', 12, { weight: 600, anchor: 'start', fill: '#6b7280' })}${text(px + 24, py + 292, '12 100,00 Kč', 20, { weight: 800, anchor: 'start', fill: '#111827' })}` : `${text(px + 24, py + 262, 'Naskenujte kód a postupujte', 12, { weight: 600, anchor: 'start', fill: '#6b7280' })}${text(px + 24, py + 280, 'podle pokynů.', 12, { weight: 600, anchor: 'start', fill: '#6b7280' })}`}
          ${img(code, b.x, b.y, b.w, b.h)}
          ${invoice ? text(cx, b.y + b.h + 16, 'QR Platba', 11, { weight: 800, fill: '#111827' }) : ''}
        </g>
        <g transform="translate(${W * 0.2} ${H * 0.86}) rotate(-24)"><rect width="${W * 0.6}" height="12" rx="6" fill="#1e3a8a"/><path d="M${W * 0.6} 0 l22 6 l-22 6z" fill="#e5e7eb"/></g>`,
      };
    },

    screen(W, H, code, s, sample) {
      const id = `s${uid++}`;
      const lw = W * 0.9, lh = lw * 0.64, lx = (W - lw) / 2, ly = H * 0.22;
      const size = lh * 0.52;
      const cx = W / 2, cy = ly + lh * 0.55;
      const b = codeBox(code, cx, cy, size);
      const label = sample?.type === 'login' ? `Přihlaste se: naskenujte kód v ${sample.fields?.service || 'aplikaci'}` : sample?.type === 'crypto' ? 'Zaplaťte kryptoměnou' : 'Naskenujte kód v telefonu';
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#20232b"/><stop offset="1" stop-color="#3a3f4a"/></linearGradient>
          <filter id="${id}bl"><feGaussianBlur stdDeviation="6"/></filter>${shadowFilter(id + 'sh', 18, 18, 0.5)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}bg)"/>
        <g filter="url(#${id}bl)">${bokeh(W, H, 10, ['#6aa9ff', '#ffffff', '#ffd08a'], 5)}</g>
        <rect x="0" y="${ly + lh + 24}" width="${W}" height="${H}" fill="#5b4a3b"/>
        <g filter="url(#${id}sh)">
          <rect x="${lx}" y="${ly}" width="${lw}" height="${lh}" rx="14" fill="#0f1115"/>
          <rect x="${lx + 10}" y="${ly + 10}" width="${lw - 20}" height="${lh - 20}" rx="6" fill="#f8fafc"/>
          <path d="M${lx - 24} ${ly + lh + 2} h${lw + 48} l-14 22 h${-(lw + 20)}z" fill="#9ca3af"/>
        </g>
        <rect x="${lx + 10}" y="${ly + 10}" width="${lw - 20}" height="26" rx="6" fill="#e2e8f0"/>
        <circle cx="${lx + 24}" cy="${ly + 23}" r="4" fill="#f87171"/><circle cx="${lx + 36}" cy="${ly + 23}" r="4" fill="#fbbf24"/><circle cx="${lx + 48}" cy="${ly + 23}" r="4" fill="#34d399"/>
        ${text(cx, ly + 58, label, 12, { weight: 700, fill: '#0f172a' })}
        ${img(code, b.x, b.y, b.w, b.h)}`,
      };
    },

    poster(W, H, code, s, sample) {
      const id = `o${uid++}`;
      const pw = W * 0.78, ph = H * 0.58, px = (W - pw) / 2, py = H * 0.12;
      const size = pw * 0.44;
      const cx = W / 2, cy = py + ph - size / 2 - 44;
      const b = codeBox(code, cx, cy, size);
      const headline = { event: 'KONCERT V PARKU', geo: 'PROHLÍDKA MĚSTA', 'url-apk': 'APLIKACE ZDARMA', crypto: 'PODPOŘTE ÚTULEK', sms: 'POMOZTE ZVÍŘATŮM' }[sample?.type] || (sample?.id?.includes('apk') ? 'APLIKACE ZDARMA' : sample?.id?.includes('vpn') || sample?.id?.includes('mobileconfig') ? 'VPN ZDARMA' : 'AKCE MĚSÍCE');
      return {
        rects: [b],
        svg: `<defs>
          <pattern id="${id}brick" width="60" height="30" patternUnits="userSpaceOnUse"><rect width="60" height="30" fill="#b9826a"/><path d="M0 0H60M0 15H60M30 0V15M0 15V30M60 15V30" stroke="#a36c55" stroke-width="2"/></pattern>
          <linearGradient id="${id}p" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7c3aed"/><stop offset=".55" stop-color="#db2777"/><stop offset="1" stop-color="#f59e0b"/></linearGradient>
          ${shadowFilter(id + 'sh', 12, 14, 0.35)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}brick)"/>
        <rect width="${W}" height="${H}" fill="#000" opacity=".12"/>
        <g filter="url(#${id}sh)">
          <rect x="${px}" y="${py}" width="${pw}" height="${ph}" rx="6" fill="url(#${id}p)"/>
          <circle cx="${px + pw * 0.8}" cy="${py + 70}" r="60" fill="#fff" opacity=".15"/>
          ${text(W / 2, py + 64, headline, 24, { weight: 900, fill: '#fff' })}
          ${text(W / 2, py + 92, '12. 10. 2026 · vstup zdarma', 13, { weight: 600, fill: '#fde68a' })}
          <rect x="${b.x - 10}" y="${b.y - 10}" width="${b.w + 20}" height="${b.h + 20}" rx="10" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}
          ${text(W / 2, b.y + b.h + 30, 'NASKENUJTE', 13, { weight: 900, fill: '#fff', ls: 2 })}
        </g>`,
      };
    },

    card(W, H, code, s, sample) {
      const id = `k${uid++}`;
      const cw = W * 0.86, ch = cw * 0.58, cxl = (W - cw) / 2, cyt = H * 0.3;
      const size = ch * 0.62;
      const cx = cxl + cw - size / 2 - 22, cy = cyt + ch / 2;
      const b = codeBox(code, cx, cy, size);
      const name = sample?.fields?.name || 'Jana Nováková';
      const org = sample?.fields?.org || (sample?.type === 'messenger' ? 'Napište nám na WhatsApp' : 'Kavárna U Lípy');
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}d" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a2d35"/><stop offset="1" stop-color="#454a55"/></linearGradient>
          ${shadowFilter(id + 'sh', 14, 14, 0.5)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}d)"/>
        <g filter="url(#${id}sh)" transform="rotate(-3 ${W / 2} ${cyt + ch / 2})">
          <rect x="${cxl}" y="${cyt}" width="${cw}" height="${ch}" rx="12" fill="#fbf7ef"/>
          <rect x="${cxl}" y="${cyt}" width="10" height="${ch}" rx="5" fill="#b45309"/>
          ${text(cxl + 26, cyt + 44, name, 17, { weight: 800, anchor: 'start', fill: '#1c1917' })}
          ${text(cxl + 26, cyt + 64, org, 11.5, { weight: 600, anchor: 'start', fill: '#78716c' })}
          ${[0, 1, 2].map((i) => `<rect x="${cxl + 26}" y="${cyt + 90 + i * 18}" width="${cw * 0.34}" height="6" rx="3" fill="#d6d3d1"/>`).join('')}
          ${img(code, b.x, b.y, b.w, b.h)}
        </g>`,
      };
    },

    windshield(W, H, code) {
      const id = `w${uid++}`;
      const size = W * 0.3;
      const cx = W / 2 + 10, cy = H * 0.46;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5b7187"/><stop offset=".6" stop-color="#9fb2c4"/><stop offset="1" stop-color="#34404d"/></linearGradient>
          <linearGradient id="${id}h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b91c1c"/><stop offset="1" stop-color="#7f1212"/></linearGradient>
          ${shadowFilter(id + 'sh', 6, 6, 0.35)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}g)"/>
        <path d="M-20 ${H * 0.12} Q${W / 2} ${H * 0.04} ${W + 20} ${H * 0.12}" stroke="#fff" stroke-width="30" opacity=".12" fill="none"/>
        <path d="M0 ${H * 0.74} Q${W / 2} ${H * 0.66} ${W} ${H * 0.74} L${W} ${H} L0 ${H}z" fill="url(#${id}h)"/>
        <g filter="url(#${id}sh)" transform="rotate(5 ${cx} ${cy})">
          <rect x="${b.x - 26}" y="${b.y - 96}" width="${b.w + 52}" height="${b.h + 150}" rx="4" fill="#fffef5"/>
          ${text(cx, b.y - 66, 'OZNÁMENÍ', 16, { weight: 900, fill: '#111' })}
          ${text(cx, b.y - 46, 'o přestupku v dopravě', 11, { weight: 600, fill: '#444' })}
          ${text(cx, b.y - 24, 'Uhraďte do 3 dnů:', 11, { weight: 700, fill: '#b91c1c' })}
          ${img(code, b.x, b.y, b.w, b.h)}
          ${text(cx, b.y + b.h + 22, 'Policie ČR', 12, { weight: 800, fill: '#1e3a8a' })}
        </g>
        <rect x="-20" y="${H * 0.62}" width="${W * 0.95}" height="9" rx="4" fill="#111" transform="rotate(-18 ${W * 0.2} ${H * 0.66})"/>`,
      };
    },

    wifi(W, H, code) {
      const id = `f${uid++}`;
      const size = W * 0.36;
      const cx = W / 2, cy = H * 0.47;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs>
          <linearGradient id="${id}w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#efe5d6"/><stop offset="1" stop-color="#d9c8b0"/></linearGradient>
          ${shadowFilter(id + 'sh', 10, 12, 0.3)}
        </defs>
        <rect width="${W}" height="${H}" fill="url(#${id}w)"/>
        <g opacity=".5">${[0.2, 0.8].map((x) => `<rect x="${W * x - 30}" y="${H * 0.08}" width="60" height="90" rx="4" fill="#c8b597"/>`).join('')}</g>
        <g filter="url(#${id}sh)">
          <rect x="${b.x - 30}" y="${b.y - 110}" width="${b.w + 60}" height="${b.h + 170}" rx="10" fill="#6b4a2b"/>
          <rect x="${b.x - 20}" y="${b.y - 100}" width="${b.w + 40}" height="${b.h + 150}" rx="6" fill="#fbf8f2"/>
          ${text(cx, b.y - 62, 'Wi‑Fi pro hosty', 20, { weight: 900, fill: '#3b2a1a' })}
          ${text(cx, b.y - 38, 'Naskenujte a připojte se', 12, { weight: 600, fill: '#7c6a58' })}
          ${img(code, b.x, b.y, b.w, b.h)}
          ${text(cx, b.y + b.h + 30, 'Kavárna U Lípy', 13, { weight: 800, fill: '#3b2a1a' })}
        </g>`,
      };
    },

    shop(W, H, code) {
      const id = `h${uid++}`;
      const size = W * 0.36;
      const cx = W / 2, cy = H * 0.45;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs><linearGradient id="${id}bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fdf2e9"/><stop offset="1" stop-color="#e8cfb4"/></linearGradient>${shadowFilter(id + 'sh', 10, 10, 0.3)}</defs>
        <rect width="${W}" height="${H}" fill="url(#${id}bg)"/>
        <rect y="${H * 0.66}" width="${W}" height="${H * 0.34}" fill="#9a6b43"/>
        <g filter="url(#${id}sh)"><rect x="${b.x - 22}" y="${b.y - 70}" width="${b.w + 44}" height="${b.h + 120}" rx="16" fill="#dc2626"/>
          ${text(cx, b.y - 36, '扫码支付 · Scan to pay', 14, { weight: 800, fill: '#fff' })}
          <rect x="${b.x - 6}" y="${b.y - 6}" width="${b.w + 12}" height="${b.h + 12}" rx="6" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}</g>`,
      };
    },

    product(W, H, code, s, sample) {
      const id = `r${uid++}`;
      const size = W * 0.26;
      const cx = W / 2 + 40, cy = H * 0.5;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs><linearGradient id="${id}bx" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fbbf24"/><stop offset="1" stop-color="#ea580c"/></linearGradient>${shadowFilter(id + 'sh', 16, 16, 0.35)}</defs>
        <rect width="${W}" height="${H}" fill="#e7e5e4"/>
        <g filter="url(#${id}sh)"><rect x="${W * 0.12}" y="${H * 0.22}" width="${W * 0.76}" height="${H * 0.52}" rx="14" fill="url(#${id}bx)"/></g>
        ${text(W * 0.2, H * 0.3, sample?.id === 'microqr-table' ? 'STŮL' : 'KÁVA ZRNKOVÁ', 22, { weight: 900, anchor: 'start', fill: '#fff' })}
        ${text(W * 0.2, H * 0.33, sample?.id === 'microqr-table' ? 'Kavárna U Lípy' : '1 kg · Kavárna U Lípy', 12, { weight: 700, anchor: 'start', fill: '#fff7ed' })}
        <rect x="${b.x - 8}" y="${b.y - 8}" width="${b.w + 16}" height="${b.h + 16}" rx="6" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}`,
      };
    },

    boarding(W, H, code) {
      const id = `a${uid++}`;
      const size = W * 0.38;
      const cx = W / 2, cy = H * 0.53;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<defs><linearGradient id="${id}bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1e293b"/><stop offset="1" stop-color="#0f172a"/></linearGradient>${shadowFilter(id + 'sh', 16, 16, 0.5)}</defs>
        <rect width="${W}" height="${H}" fill="url(#${id}bg)"/>
        <g filter="url(#${id}sh)"><rect x="${W * 0.1}" y="${H * 0.2}" width="${W * 0.8}" height="${H * 0.58}" rx="22" fill="#fff"/></g>
        <rect x="${W * 0.1}" y="${H * 0.2}" width="${W * 0.8}" height="64" rx="22" fill="#00a1de"/><rect x="${W * 0.1}" y="${H * 0.2 + 40}" width="${W * 0.8}" height="24" fill="#00a1de"/>
        ${text(W * 0.16, H * 0.2 + 40, 'BOARDING PASS', 15, { weight: 800, anchor: 'start', fill: '#fff' })}
        ${text(W * 0.22, H * 0.2 + 118, 'PRG', 34, { weight: 900, fill: '#0f172a' })}${text(W * 0.78, H * 0.2 + 118, 'AMS', 34, { weight: 900, fill: '#0f172a' })}
        ${text(W / 2, H * 0.2 + 112, '✈', 22, { fill: '#00a1de' })}
        ${img(code, b.x, b.y, b.w, b.h)}`,
      };
    },

    screenshot(W, H, code) {
      const size = W * 0.5;
      const cx = W / 2, cy = H * 0.56;
      const b = codeBox(code, cx, cy, size);
      return {
        rects: [b],
        svg: `<rect width="${W}" height="${H}" fill="#f2f2f7"/><rect x="0" y="0" width="${W}" height="${H * 0.1}" fill="#fff"/>
        ${text(W / 2, H * 0.07, 'Zásilkovna', 16, { weight: 700, fill: '#111' })}
        <rect x="${W * 0.06}" y="${H * 0.15}" width="${W * 0.72}" height="${H * 0.16}" rx="18" fill="#e5e5ea"/>
        ${text(W * 0.1, H * 0.2, 'Vaše zásilka čeká na doplatek', 13, { weight: 600, anchor: 'start', fill: '#111' })}
        ${text(W * 0.1, H * 0.235, '29 Kč. Naskenujte kód:', 13, { weight: 600, anchor: 'start', fill: '#111' })}
        <rect x="${b.x - 10}" y="${b.y - 10}" width="${b.w + 20}" height="${b.h + 20}" rx="12" fill="#fff"/>${img(code, b.x, b.y, b.w, b.h)}`,
      };
    },

    landscape(W, H) {
      const id = `x${uid++}`;
      return {
        rects: [],
        svg: `<defs><linearGradient id="${id}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbbf77"/><stop offset=".6" stop-color="#f472b6"/><stop offset="1" stop-color="#312e81"/></linearGradient></defs>
        <rect width="${W}" height="${H}" fill="url(#${id}s)"/><circle cx="${W * 0.7}" cy="${H * 0.38}" r="${W * 0.14}" fill="#fde68a"/>
        <path d="M0 ${H * 0.7} L${W * 0.3} ${H * 0.5} L${W * 0.55} ${H * 0.66} L${W * 0.8} ${H * 0.46} L${W} ${H * 0.6} L${W} ${H} L0 ${H}z" fill="#1e1b4b"/>`,
      };
    },
  };

  function build(sceneId, W, H, code, extra = {}, sample = null) {
    const fn = SCENES[sceneId] || SCENES.poster;
    const r = fn(W, H, code, extra, sample);
    return { svg: `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${r.svg}</svg>`, rects: r.rects };
  }

  return { build };
})();
