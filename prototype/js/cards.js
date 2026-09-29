/* Result-sheet building blocks: verdict header, meter, reasons, consequences, type cards, actions.
   Structure (Codex UX review): compact verdict → expressive type card → top 1–2 reasons →
   primary action → "Podrobnosti kontroly". Facts sit on opaque surfaces; glass is chrome only. */
window.BQ = window.BQ || {};

BQ.cards = (function () {
  const t = (k, a) => BQ.t(k, a);
  const esc = (s) => BQ.esc(s);
  const I = (n, c) => BQ.icon(n, c);

  const TYPE_ICON = {
    url: 'globe', spd: 'banknote', sid: 'receipt', epc: 'banknote', spc: 'banknote', crypto: 'bitcoin', paybysquare: 'banknote',
    sms: 'message', tel: 'phone', mailto: 'envelope', contact: 'person', wifi: 'wifi', event: 'calendar', webcal: 'calendar',
    geo: 'mapPin', otpauth: 'key', 'otpauth-migration': 'key', login: 'deviceLink', fido: 'fingerprint', seed: 'key',
    walletconnect: 'link', 'app-install': 'app', store: 'store', messenger: 'chat', 'data-uri': 'code', 'js-uri': 'code',
    intent: 'android', emvco: 'cart', gs1: 'box', bcbp: 'plane', hc1: 'health', text: 'doc',
  };
  const CSQ_ICON = {
    'csq.call_forwarding': 'phone', 'csq.premium_call': 'phone', 'csq.premium_sms': 'message', 'csq.twofa_secrets': 'key', 'csq.seed_phrase': 'key',
    'csq.account_access': 'deviceLink', 'csq.wallet_connect': 'link', 'csq.profile_install': 'profile', 'csq.app_install': 'app',
    'csq.subscription_charge': 'repeat', 'csq.billing_gateway': 'antenna', 'csq.executable_content': 'code', 'csq.invalid_payment': 'banknote',
  };
  const typeName = (type) => t(`type.${type}`);
  const typeIcon = (type) => TYPE_ICON[type] || 'qr';

  function evidenceSorted(sample) {
    const W = window.BQ_DATA.weights.signals;
    return [...(sample.signals || [])].sort((a, b) => (W[b.id]?.weight || 0) - (W[a.id]?.weight || 0));
  }
  function consequences(sample) {
    const order = { critical: 0, warning: 1, info: 2 };
    return (sample.consequences || []).map((c) => ({ ...BQ.sig.consequence(c.id, c.args), id: c.id })).sort((a, b) => order[a.severity] - order[b.severity]);
  }

  /* ───────────── Verdict header ───────────── */
  function headerModel(sample, a) {
    const ev = evidenceSorted(sample);
    const top = ev[0] ? BQ.sig.evidence(ev[0].id, ev[0].args) : null;
    const csq = consequences(sample);
    const critical = csq.find((c) => c.severity === 'critical');
    const warning = csq.find((c) => c.severity === 'warning');
    const kicker = typeName(sample.type);
    if (a.band === 'danger') return { cls: 'v-danger', mood: 'danger', icon: 'octagon', anim: 'anim-pulse', kicker, title: t('band.danger'), sub: top ? `${top.title}. ${top.implication}` : '' };
    if (critical) return { cls: 'v-alert', mood: 'alert', icon: CSQ_ICON[critical.id] || 'triangle', anim: 'anim-wiggle', kicker: `${kicker} · ${t('band.alertKicker')}`, title: critical.title, sub: '' };
    if (a.band === 'caution') return { cls: 'v-caution', mood: 'caution', icon: 'triangle', anim: 'anim-wiggle', kicker, title: t('band.caution'), sub: top ? top.title : '' };
    if (a.band === 'incomplete') return { cls: 'v-incomplete', mood: 'incomplete', icon: 'cloudOff', anim: '', kicker, title: t('band.incomplete'), sub: BQ.sig.incomplete(sample.completeness?.reason) };
    if (a.band === 'info') return { cls: 'v-info', mood: 'info', icon: typeIcon(sample.type), anim: '', kicker: '', title: typeName(sample.type), sub: '', chip: warning ? { cls: 'caution', text: warning.title } : { cls: 'safe', text: t('band.infoChip') } };
    return { cls: 'v-safe', mood: 'safe', icon: 'shieldCheck', anim: 'anim-draw', kicker, title: t('band.safe'), sub: t('band.safeSub'), chip: warning ? { cls: 'caution', text: warning.title } : null };
  }

  function header(sample, a, style) {
    const m = headerModel(sample, a);
    const visual = style === 'mascot'
      ? BQ.mascot(m.mood, 76)
      : `<div class="verdict-badge ${m.anim} anim-pop">${I(m.icon)}</div>`;
    return `<div class="verdict ${m.cls}" role="status" aria-live="polite">
      <div class="verdict-visual">${visual}</div>
      <div class="verdict-text">
        ${m.kicker ? `<div class="verdict-kicker">${esc(m.kicker)}</div>` : ''}
        <h2>${esc(m.title)}</h2>
        ${m.sub ? `<p>${m.sub}</p>` : ''}
        ${m.chip ? `<div class="chip-row"><span class="chip ${m.chip.cls}">${m.chip.cls === 'safe' ? I('check') : I('triangle')} ${esc(m.chip.text)}</span></div>` : ''}
      </div>
    </div>`;
  }

  function meter(sample, a) {
    if (!a.scored || sample.decodeOnly) return '';
    const m = headerModel(sample, a);
    const muted = a.band === 'incomplete';
    const label = m.cls === 'v-alert' ? t('meter.fraud') : t('meter.label');
    return `<div class="meter" aria-label="${esc(label)} ${a.score} / 100">
      <div class="meter-head"><span>${esc(label)}</span><b>${a.score}<small>/100</small></b></div>
      <div class="meter-track ${muted ? 'muted' : ''}"><span class="meter-marker" style="left:${Math.max(3, Math.min(97, a.score))}%"></span></div>
      <div class="meter-scale"><span>${t('meter.low')}</span><span>${t('meter.mid')}</span><span>${t('meter.high')}</span></div>
      <div class="meter-note">${muted ? t('meter.muted', { score: a.score }) : t('meter.note')}</div>
    </div>`;
  }

  /* ───────────── Reasons, consequences, checks ───────────── */
  function reasonHTML(sig) {
    const W = window.BQ_DATA.weights.signals[sig.id];
    const e = BQ.sig.evidence(sig.id, sig.args);
    const w = W?.weight || 0;
    const cls = w >= 2 ? 'ri-danger' : w >= 1 ? 'ri-caution' : 'ri-weak';
    const icon = w >= 2 ? 'octagon' : w >= 1 ? 'triangle' : 'info';
    return `<div class="reason"><div class="reason-icon ${cls}">${I(icon)}</div><div>
      <h4>${e.title}</h4><p>${e.observation}</p><p class="impl">${e.implication}</p><p class="act">${I('arrowRight')}<span>${e.action}</span></p></div></div>`;
  }
  function topReasons(sample, a) {
    const ev = evidenceSorted(sample);
    if (!ev.length || a.band === 'safe' || a.band === 'info') return '';
    return `<div class="section-title">${t('sec.why')}</div><div class="card">${ev.slice(0, 2).map(reasonHTML).join('')}</div>`;
  }
  function moreReasons(sample) {
    const ev = evidenceSorted(sample);
    return ev.length > 2 ? `<div class="sub-h">${t('sec.more')}</div>${ev.slice(2).map(reasonHTML).join('')}` : '';
  }
  function weakNotes(sample, a) {
    // Weak evidence under a safe/incomplete band is still shown, quietly, in details.
    if (a.band !== 'safe' && a.band !== 'info' && a.band !== 'incomplete') return '';
    const ev = evidenceSorted(sample);
    return ev.length ? `<div class="sub-h">${t('sec.more')}</div>${ev.map(reasonHTML).join('')}` : '';
  }
  function consequenceHTML(sample) {
    const cs = consequences(sample);
    if (!cs.length) return '';
    return `<div class="section-title">${t('sec.consequence')}</div>` + cs.map((c) => `<div class="consequence cq-${c.severity}">${I(c.severity === 'info' ? 'info' : 'triangle')}<div><h4>${c.title}</h4><p>${c.text}</p></div></div>`).join('');
  }
  function checksHTML(sample, limit) {
    const list = (sample.checks || []).slice(0, limit || 99);
    if (!list.length) return '';
    return `<ul class="checks">${list.map((c) => `<li>${I('check')}<span>${BQ.sig.check(c.id, c.args)}</span></li>`).join('')}</ul>`;
  }
  function completenessNotice(sample, a) {
    const c = sample.completeness || {};
    if (c.state !== 'incomplete' && c.state !== 'skipped') return '';
    const manual = c.state === 'skipped'
      ? (c.manual ? `<div><button class="link-btn" data-action="manual-check">${t('sec.manual')}</button></div>` : `<div>${t('sec.noManual')}</div>`)
      : '';
    // Under the "Nelze ověřit" header the reason is already the subtitle — show only the next step.
    if (a && a.band === 'incomplete') return manual ? `<div class="notice">${I('info')}${manual}</div>` : '';
    return `<div class="notice">${I('cloudOff')}<div><b>${t('sec.incomplete')}.</b> ${BQ.sig.incomplete(c.reason)}${manual}</div></div>`;
  }

  /* ───────────── Type cards ───────────── */
  const bankColors = { '0800': '#2870ed', '0100': '#e2231a', '0300': '#003e7e', '2010': '#1c9e4b', '0600': '#3c3c3c', '5500': '#fee600', '3030': '#7ab928', '0710': '#8a1538' };
  function bankLogo(code, name) {
    const bg = bankColors[code] || `hsl(${BQ.fmt.hue(code || name)} 45% 42%)`;
    const fg = code === '5500' ? '#111' : '#fff';
    const letters = (name || '??').replace(/[^A-ZČŘŠŽÁÉÍÓÚ]/g, '').slice(0, 2) || '?';
    return `<span class="bank-logo" style="background:${bg};color:${fg}">${esc(letters)}</span>`;
  }

  function urlCard(s) {
    const f = s.fields, ins = s.inspection || {};
    const final = ins.final;
    const host = final?.host || f.hostDisplay || f.host;
    const reg = final?.registrable || f.registrable;
    const shownUrl = final?.url || f.display || f.url;
    const chain = ins.chain || [];
    let journey = '';
    if (chain.length) {
      journey = chain.map((h, i) => {
        const u = safeURL(h.url);
        const last = i === chain.length - 1;
        const cls = h.stopped ? 'stopped' : last && final ? 'final' : '';
        const meta = h.stopped === 'billing' ? t('url.stoppedBilling') : h.stopped === 'timeout' ? t('url.stoppedTimeout')
          : [h.status ? `${h.status}${h.status >= 300 && h.status < 400 ? ' · ' + t('url.redirect') : ''}` : '', h.kind === 'shortener' ? t('url.shortener') : '', h.kind === 'https-upgrade' ? t('url.https') : ''].filter(Boolean).join(' · ');
        return `<li class="${cls}"><span class="dot"></span><div class="host">${esc(u.host)}</div><div class="meta">${esc(meta)}</div></li>`;
      }).join('');
      if (!final) journey += `<li class="unknown"><span class="dot"></span><div class="meta">${t('url.unknownTarget')}</div></li>`;
    } else {
      journey = `<li><span class="dot"></span><div class="host">${esc(f.hostDisplay || f.host)}</div></li><li class="unknown"><span class="dot"></span><div class="meta">${t('url.unknownTarget')}</div></li>`;
    }
    const page = ins.page;
    const asks = page ? (page.asks?.length ? page.asks.map((k) => `<span class="chip ${k === 'card' || k === 'password' || k === 'phone' ? 'caution' : ''}">${esc(t('ask.' + k))}</span>`).join('') : `<span class="chip safe">${I('check')} ${t('url.nothing')}</span>`) : '';
    const offer = page?.offer ? `<div class="claim"><em>${t('url.smallPrint')}</em><span class="offer-hl">„${esc(page.offer.text)}“</span></div>` : '';
    return `<div class="tcard">
      <div class="label">${t('url.target')}</div>
      <div class="domain-big">${BQ.fmt.hostHTML(host, reg)}</div>
      <div class="mono">${esc(shownUrl)}</div>
      ${f.userinfo ? `<div class="fine">${I('triangle')}<span>${esc(f.userinfo)}@ — ${t('url.userinfo')}</span></div>` : ''}
      ${f.inner ? `<div class="fine">${I('link')}<span>${t('url.inner')}: <b>${esc(f.inner)}</b></span></div>` : ''}
      ${f.upgraded ? `<div class="fine">${I('lock')}<span>${BQ.sig.check('chk.https_upgraded')}</span></div>` : ''}
      <div class="sub-h">${t('url.journey')}</div>
      <ol class="journey">${journey}</ol>
      ${page ? `<div class="sub-h">${t('url.asks')}</div><div class="asks">${asks}</div>` : ''}
      ${offer}
      ${page?.title ? `<div class="claim"><em>${t('url.claim')}</em>„${esc(page.title)}“</div>` : ''}
    </div>`;
  }
  function safeURL(u) { try { return new URL(u); } catch { return { host: u }; } }

  function paymentCard(s) {
    const f = s.fields;
    const intent = f.kind === 'standing' ? { cls: 'recurring', icon: 'repeat', text: t('pay.standing') }
      : f.kind === 'directDebit' ? { cls: 'debit', icon: 'repeat', text: t('pay.debit') }
      : f.invoice ? { cls: '', icon: 'receipt', text: `${t('pay.oneoff')} · ${t('pay.invoice')}` }
      : { cls: '', icon: 'banknote', text: t('pay.oneoff') };
    const amt = BQ.fmt.amount(f.amount, f.currency);
    const amount = f.amountRaw ? `<div class="amount missing">${t('pay.invalidAmount')}: „${esc(f.amountRaw)}“</div>`
      : amt ? `<div class="amount">${esc(amt.num)}<small>${esc(amt.sym)}</small></div>` : `<div class="amount missing">${t('pay.noAmount')}</div>`;
    const bankName = f.bankName || (f.country ? `${t('pay.foreign')} (${f.country})` : t('pay.bankUnknown'));
    const syms = [['VS', f.vs], ['SS', f.ss], ['KS', f.ks]].filter(([, v]) => v).map(([k, v]) => `<span class="sym">${k} <b>${esc(v)}</b></span>`).join('');
    const dates = [];
    if (f.kind === 'standing' && f.dueDate) dates.push([t('pay.first'), BQ.fmt.date(f.dueDate)]);
    else if (f.kind === 'directDebit') { dates.push([t('pay.limit'), amt ? `${amt.num} ${amt.sym}` : '—']); if (f.lastDate) dates.push([t('pay.until'), BQ.fmt.date(f.lastDate)]); }
    else if (f.dueDate) dates.push([t('pay.due'), BQ.fmt.date(f.dueDate)]);
    if (f.message) dates.push([t('pay.msg'), f.message]);
    const inv = f.invoice ? `<div class="sub-h">${t('pay.invoice')}</div><dl class="kv">
        <dt>${t('inv.number')}</dt><dd>${esc(f.invoice.id)}</dd><dt>${t('inv.issued')}</dt><dd>${BQ.fmt.date(f.invoice.issued)}</dd>
        <dt>${t('inv.issuer')}</dt><dd>${esc(f.invoice.issuerIco)} / ${esc(f.invoice.issuerVat)}</dd>
        <dt>${t('inv.base')}</dt><dd>${esc(BQ.fmt.amount(f.invoice.base, 'CZK').num)} Kč</dd><dt>${t('inv.vat')}</dt><dd>${esc(BQ.fmt.amount(f.invoice.vat, 'CZK').num)} Kč</dd></dl>` : '';
    return `<div class="receipt">
      <span class="intent ${intent.cls}">${I(intent.icon)} ${intent.text}</span>
      ${f.paymentType === 'IP' ? ` <span class="intent">${I('bolt')} ${t('pay.instant')}</span>` : ''}
      ${amount}
      <div class="acct">
        <div class="label">${t('pay.to')}</div>
        <div class="num">${esc(f.domestic || BQ.fmt.iban(f.iban))}</div>
        <div class="bank">${f.bankCode ? bankLogo(f.bankCode, f.bankName) : I('globe')} <span>${esc(bankName)}</span></div>
        <div class="iban">IBAN ${esc(BQ.fmt.iban(f.iban))}</div>
        ${f.recipientName ? `<div class="claim"><em>${t('pay.rn')}</em>„${esc(f.recipientName)}“</div>` : ''}
      </div>
      ${syms ? `<div class="sym-chips">${syms}</div>` : ''}
      ${dates.length ? `<dl class="kv">${dates.map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join('')}</dl>` : ''}
      ${inv}
      <div class="fine">${I('info')}<span>${t('pay.formatOnly')}</span></div>
    </div>`;
  }

  function sidCard(s) {
    const f = s.fields;
    const a = BQ.fmt.amount(f.total, f.currency);
    return `<div class="receipt"><span class="intent">${I('receipt')} ${t('pay.invoice')}</span>
      <div class="amount">${esc(a.num)}<small>${esc(a.sym)}</small></div>
      <dl class="kv"><dt>${t('inv.number')}</dt><dd>${esc(f.id)}</dd><dt>${t('inv.issued')}</dt><dd>${BQ.fmt.date(f.issued)}</dd>
      <dt>${t('pay.due')}</dt><dd>${BQ.fmt.date(f.due)}</dd><dt>${t('inv.taxPoint')}</dt><dd>${BQ.fmt.date(f.taxPoint)}</dd>
      <dt>${t('inv.issuer')}</dt><dd>${esc(f.issuerIco)} / ${esc(f.issuerVat)}</dd><dt>${t('inv.base')}</dt><dd>${esc(BQ.fmt.amount(f.base, 'CZK').num)} Kč</dd>
      <dt>${t('inv.vat')}</dt><dd>${esc(BQ.fmt.amount(f.vat, 'CZK').num)} Kč</dd><dt>VS</dt><dd>${esc(f.vs)}</dd></dl>
      <div class="fine">${I('info')}<span>IBAN ${esc(BQ.fmt.iban(f.iban))}</span></div></div>`;
  }

  function euroCard(s) {
    const f = s.fields;
    const a = BQ.fmt.amount(f.amount, f.currency);
    const name = f.name || f.creditor;
    return `<div class="receipt"><span class="intent">${I('banknote')} ${t('pay.oneoff')} · ${s.type === 'spc' ? 'QR-bill' : 'SEPA'}</span>
      <div class="amount">${esc(a.num)}<small>${esc(a.sym)}</small></div>
      <div class="acct"><div class="label">${t('pay.to')}</div><div class="num" style="font-size:1.05em">${esc(name)}</div>
      <div class="iban">IBAN ${esc(BQ.fmt.iban(f.iban))}${f.bic ? ' · BIC ' + esc(f.bic) : ''}</div>
      <div class="claim"><em>${t('pay.rn')}</em>„${esc(name)}“</div></div>
      ${f.reference ? `<div class="sym-chips"><span class="sym">${esc(f.referenceType)} <b>${esc(f.reference)}</b></span></div>` : ''}
      ${f.text || f.message ? `<dl class="kv"><dt>${t('pay.msg')}</dt><dd>${esc(f.text || f.message)}</dd></dl>` : ''}
      <div class="fine">${I('info')}<span>${t('pay.formatOnly')}</span></div></div>`;
  }

  function cryptoCard(s) {
    const f = s.fields;
    const addr = f.recipient || f.address;
    const chunks = addr ? addr.match(/.{1,4}/g).join(' ') : '';
    return `<div class="tcard"><div class="type-chip">${I('bitcoin')} ${esc(f.network)}</div>
      <div class="amount" style="font-size:calc(38px * var(--fs))">${esc(f.amount)}<small>${esc(f.unit)}</small></div>
      ${f.label || f.description ? `<div class="label">„${esc(f.label || f.description)}“</div>` : ''}
      ${addr ? `<div class="sub-h">${f.recipient ? t('crypto.recipient') : t('crypto.address')}</div><div class="mono" style="font-size:calc(15px * var(--fs));color:var(--label)">${esc(chunks)}</div>` : ''}
      ${f.contract ? `<div class="sub-h">${t('crypto.token')}</div><div class="mono">${esc(f.token)} · ${esc(f.contract)}</div>` : ''}
      ${f.invoice ? `<div class="sub-h">Lightning</div><div class="mono">${esc(f.invoice)}</div>` : ''}</div>`;
  }

  function smsCard(s) {
    const f = s.fields;
    return `<div class="tcard phone-card"><div class="dial" style="padding:6px 0 0">
        <div class="label">${t('sms.to')}</div><div class="dnum">${esc(f.numberDisplay)}</div>
        ${f.premium ? `<div class="price-tag">${esc(f.premium.price || '? Kč')}</div>` : f.charity ? `<div class="chip info" style="margin-top:8px">DMS</div>` : ''}
      </div>
      <div class="bubble-wrap"><div class="bubble-to">${t('sms.to')}: ${esc(f.numberDisplay)}</div><div class="bubble">${esc(f.body)}</div></div></div>`;
  }

  function telCard(s) {
    const f = s.fields;
    return `<div class="tcard dial"><div class="dnum ${f.numberDisplay.length > 16 ? 'long' : ''}">${esc(f.numberDisplay)}</div><div class="dkind">${esc(BQ.pick(f.kind) || '')}</div>
      ${f.premium ? `<div class="price-tag">${esc(f.premium.price)}</div>` : ''}
      ${f.mmi ? `<div class="chip alert" style="margin-top:10px">${I('phone')} ${esc(BQ.pick(f.mmi.service))} → ${esc(f.mmi.target)}</div>` : ''}</div>`;
  }

  function mailCard(s) {
    const f = s.fields;
    const [user, dom] = f.to.split('@');
    return `<div class="envelope"><dl class="kv" style="margin-top:0"><dt>${t('mail.to')}</dt><dd>${esc(user)}@${BQ.fmt.hostHTML(dom, f.registrable)}</dd>
      <dt>${t('mail.subject')}</dt><dd>${esc(f.subject)}</dd></dl><div class="claim">${esc(f.body)}</div></div>`;
  }

  function contactCard(s, ctx) {
    const f = s.fields;
    const hue = BQ.fmt.hue(f.name);
    const rows = [
      ...(f.tels || []).map((v) => ({ icon: 'phone', v })),
      ...(f.emails || []).map((v) => ({ icon: 'envelope', v })),
      ...(f.urls || []).map((v) => ({ icon: 'globe', v, flag: v === f.flaggedUrl })),
    ];
    return `<div class="bizcard" style="background:linear-gradient(135deg, hsl(${hue} 70% 46%), hsl(${(hue + 40) % 360} 75% 38%))">
      <div class="avatar">${esc(BQ.fmt.initials(f.name))}</div>
      <h3>${esc(f.name)}</h3>
      <div class="role">${esc([f.title, f.org].filter(Boolean).join(' · '))}</div>
      <div class="rows">${rows.map((r) => `<div class="row ${r.flag ? 'flag' : ''}">${I(r.icon)}<span>${esc(r.v)}</span>${r.flag ? `<span class="rv">${t('band.caution')}</span>` : ''}</div>`).join('')}</div>
    </div>
    ${f.address ? `<details class="more"><summary>${t('contact.more')} ${I('chevronRight')}</summary><div class="more-body"><dl class="kv"><dt>${I('mapPin')}</dt><dd>${esc(f.address)}</dd><dt>vCard</dt><dd>${esc(f.format)}</dd></dl></div></details>` : ''}`;
  }

  function wifiCard(s, ctx) {
    const f = s.fields;
    const sec = f.security === 'open' ? t('wifi.open') : f.security;
    const pw = f.password ? `<div class="pw"><span>${ctx.revealPw ? esc(f.password) : '••••••••'}</span><button data-action="toggle-pw">${ctx.revealPw ? t('wifi.hide') : t('wifi.show')}</button></div>` : '';
    return `<div class="tcard wifi-card"><div class="wifi-glyph">${I('wifi')}</div><div class="ssid">${esc(f.ssid)}</div>
      <div class="chip-row" style="justify-content:center"><span class="chip ${f.security === 'open' || f.security === 'WEP' ? 'caution' : 'safe'}">${I(f.security === 'open' ? 'unlock' : 'lock')} ${t('wifi.security')}: ${esc(sec)}</span>${f.hidden ? `<span class="chip">${t('wifi.hidden')}</span>` : ''}</div>
      ${pw}<div class="fine" style="justify-content:center">${I('info')}<span>${t('wifi.operator')}</span></div></div>`;
  }

  function eventCard(s) {
    const f = s.fields;
    const d = new Date(f.start);
    const month = d.toLocaleDateString(BQ.lang === 'cs' ? 'cs-CZ' : 'en-GB', { month: 'short' });
    const time = `${BQ.fmt.time(f.start)}–${BQ.fmt.time(f.end)}`;
    return `<div class="tcard"><div class="cal"><div class="cal-tile"><div class="m">${esc(month)}</div><div class="d">${d.getDate()}</div></div>
      <div><div class="big">${esc(f.summary)}</div><div class="label">${esc(time)}</div><div class="label">${I('mapPin', '')} ${esc(f.location)}</div></div></div>
      ${f.description ? `<div class="claim">${esc(f.description)}</div>` : ''}</div>`;
  }

  function geoCard(s) {
    const f = s.fields;
    return `<div class="tcard"><div class="map"><svg viewBox="0 0 360 180"><rect width="360" height="180" fill="#e8efe3"/>
      <path d="M0 120 C80 100 120 150 200 120 S320 90 360 110" stroke="#9ec5f0" stroke-width="18" fill="none"/>
      <path d="M40 0 L90 180 M0 60 L360 40 M250 0 L220 180 M0 150 L360 170" stroke="#fff" stroke-width="7"/>
      <rect x="120" y="60" width="60" height="40" fill="#d7cfc0"/><rect x="200" y="70" width="40" height="30" fill="#d7cfc0"/>
      <g transform="translate(180 88)"><path d="M0 0 c-14 -18 -14 -34 0 -34 s14 16 0 34z" fill="#ff3b30"/><circle cx="0" cy="-22" r="5" fill="#fff"/></g></svg></div>
      <div class="big">${esc(f.label)}</div><div class="label">${t('geo.coords')}: ${f.lat}, ${f.lon}</div></div>`;
  }

  function secureCard(s, glyph, title, body) {
    return `<div class="tcard secure-card"><div class="sglyph">${I(glyph)}</div><h3>${title}</h3>${body || ''}</div>`;
  }

  function typeCard(s, ctx = {}) {
    const f = s.fields || {};
    switch (s.type) {
      case 'url': return urlCard(s);
      case 'spd': return paymentCard(s);
      case 'sid': return sidCard(s);
      case 'epc': case 'spc': return euroCard(s);
      case 'crypto': return cryptoCard(s);
      case 'paybysquare': return secureCard(s, 'banknote', 'PAY by square', `<p>${t('pbs.text')}</p>`);
      case 'sms': return smsCard(s);
      case 'tel': return telCard(s);
      case 'mailto': return mailCard(s);
      case 'contact': return contactCard(s, ctx);
      case 'wifi': return wifiCard(s, ctx);
      case 'event': return eventCard(s);
      case 'webcal': return `<div class="tcard"><div class="type-chip">${I('calendar')} webcal</div><div class="domain-big">${BQ.fmt.hostHTML(f.host, f.registrable)}</div><div class="mono">${esc(f.url)}</div></div>`;
      case 'geo': return geoCard(s);
      case 'otpauth': return secureCard(s, 'key', esc(f.issuer), `<p>${t('otp.account')}: <b>${esc(f.account)}</b> · ${esc(f.kind)} · ${f.digits} číslic</p><div class="hidden-secret">${'<i></i>'.repeat(8)}</div><p>${t('otp.secretHidden')}</p>`);
      case 'otpauth-migration': return secureCard(s, 'key', t('mig.accounts'), `<div class="chip-row" style="justify-content:center">${f.issuers.map((i) => `<span class="chip">${esc(i)}</span>`).join('')}</div><div class="hidden-secret">${'<i></i>'.repeat(8)}</div><p>${t('otp.secretHidden')}</p>`);
      case 'login': return secureCard(s, 'deviceLink', esc(f.service), `<p>${esc(typeName('login'))}</p>`);
      case 'fido': return secureCard(s, 'fingerprint', 'Passkey', `<p>FIDO · hybrid</p>`);
      case 'seed': return secureCard(s, 'key', t('seed.words', { n: f.words }), `<div class="hidden-secret">${'<i></i>'.repeat(12)}</div>`);
      case 'walletconnect': return secureCard(s, 'link', 'WalletConnect', `<p>v${f.version} · relay ${esc(f.relay)}</p>`);
      case 'app-install': return `<div class="tcard"><div class="type-chip">${I('app')} itms-services</div><div class="sub-h">Manifest</div><div class="domain-big">${BQ.fmt.hostHTML(f.host, f.registrable)}</div><div class="mono">${esc(f.manifest)}</div></div>`;
      case 'store': return `<div class="tcard product-card"><div class="pbox" style="background:linear-gradient(135deg,#1c9bf0,#5856d6)">${I('store')}</div><div><div class="big">${esc(f.store)}</div><div class="label">${t('store.appId')}: ${esc(f.appId)}</div><div class="mono">${esc(f.url)}</div></div></div>`;
      case 'messenger': return `<div class="tcard product-card"><div class="pbox" style="background:${f.service === 'WhatsApp' ? '#25d366' : '#2aabee'}">${I('chat')}</div><div><div class="big">${esc(f.service)}</div><div class="label">${t('chat.target')}: <b>${esc(f.target)}</b></div>${f.text ? `<div class="bubble imessage" style="margin:8px 0 0">${esc(f.text)}</div>` : ''}</div></div>`;
      case 'data-uri': return `<div class="tcard"><div class="type-chip">${I('code')} ${esc(f.mime)}</div><div class="sub-h">${t('code.content')}</div><div class="codeblock">${esc(f.preview)}</div></div>`;
      case 'js-uri': return `<div class="tcard"><div class="type-chip">${I('code')} javascript:</div><div class="sub-h">${t('code.content')}</div><div class="codeblock">${esc(f.code)}</div></div>`;
      case 'intent': return `<div class="tcard"><div class="type-chip">${I('android')} Android intent</div><dl class="kv"><dt>${t('intent.package')}</dt><dd>${esc(f.package)}</dd></dl><div class="sub-h">${t('intent.fallback')}</div><div class="domain-big">${BQ.fmt.hostHTML(f.host, f.registrable)}</div><div class="mono">${esc(f.fallback)}</div></div>`;
      case 'emvco': return `<div class="tcard"><div class="type-chip">${I('cart')} EMVCo</div><div class="big" style="margin-top:8px">${esc(f.merchant)}</div><dl class="kv"><dt>${t('emv.city')}</dt><dd>${esc(f.city)}, ${esc(f.country)}</dd><dt>${t('emv.amount')}</dt><dd>${esc(f.amount)} (${esc(f.currencyCode)})</dd></dl></div>`;
      case 'gs1': return `<div class="tcard product-card"><div class="pbox">${I('box')}</div><div><div class="big">GTIN ${esc(f.gtin)}</div><dl class="kv"><dt>${t('gs1.batch')}</dt><dd>${esc(f.batch)}</dd><dt>${t('gs1.expiry')}</dt><dd>${BQ.fmt.date(f.expiry)}</dd></dl><div class="mono">${esc(f.host)}</div></div></div>`;
      case 'bcbp': return `<div class="boarding"><div class="bp-head"><span>${esc(f.carrier)} ${esc(f.flight)}</span><span>${esc(BQ.pick(f.date))}</span></div>
        <div class="bp-route"><span class="iata">${esc(f.from)}</span>${I('plane')}<span class="iata">${esc(f.to)}</span></div>
        <div class="bp-foot"><div>${t('bcbp.seat')}<b>${esc(f.seat)}</b></div><div>${t('bcbp.flight')}<b>${esc(f.carrier)}${esc(f.flight)}</b></div><div>PNR<b>••••••</b></div></div></div>`;
      case 'hc1': return secureCard(s, 'health', typeName('hc1'), `<p>${t('hc1.text')}</p>`);
      case 'text': return noteCard(s);
      default: return `<div class="tcard"><div class="mono">${esc(s.payload)}</div></div>`;
    }
  }

  function noteCard(s) {
    let html = esc(s.fields.text);
    for (const e of s.fields.entities || []) html = html.replace(esc(e.value), `<mark>${esc(e.value)}</mark>`);
    return `<div class="note-card"><div class="label" style="margin-bottom:6px">${t('text.label')}</div>${html}</div>`;
  }

  /* ───────────── Actions ───────────── */
  function btn(act, label, kind = 'primary', icon = '', extra = '') {
    if (kind === 'hold') {
      return `<button class="btn btn-danger-plain hold" data-hold="${act}" ${extra}><span class="hold-fill"></span>${I('hand')} ${label}</button>
        <div class="hold-alt"><button data-action="act" data-act="confirm-${act}">${t('act.holdAlt')}</button></div>`;
    }
    const cls = { primary: 'btn btn-primary', secondary: 'btn btn-secondary', plain: 'btn btn-plain' }[kind];
    return `<button class="${cls}" data-action="act" data-act="${act}" ${extra}>${icon ? I(icon) : ''}${label}</button>`;
  }

  function actions(s, a, ctx) {
    const f = s.fields || {};
    const hm = headerModel(s, a);
    const critical = hm.cls === 'v-alert';
    const out = [];
    const danger = a.band === 'danger';
    const hasPage = !!s.inspection?.page;
    switch (s.type) {
      case 'url': case 'store': case 'messenger': {
        const openLabel = s.type === 'store' ? t('act.appStore') : s.type === 'messenger' ? t('act.openService', { service: f.service }) : t('act.openWeb');
        if (s.subtype === 'profile') { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('install', t('act.install'), 'hold')); break; }
        if (s.subtype === 'download') { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('open', t('act.openAnyway'), 'plain')); break; }
        if (danger) { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('open', t('act.hold'), 'hold')); break; }
        if (critical) { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('open', t('act.continueHold'), 'hold')); break; }
        if (a.band === 'caution') { if (hasPage) out.push(btn('preview', t('act.preview'), 'primary', 'eye')); else out.push(btn('back', t('act.back'), 'primary')); out.push(btn('open', t('act.openAnyway'), 'secondary')); break; }
        if (a.band === 'incomplete') { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('open', t('act.openAnyway'), 'secondary')); break; }
        out.push(btn('open', openLabel, 'primary', s.type === 'url' ? 'compass' : ''));
        if (hasPage) out.push(btn('preview', t('act.preview'), 'secondary', 'eye'));
        break;
      }
      case 'webcal': out.push(btn('back', t('act.back'), 'primary')); out.push(btn('subscribe', t('act.subscribe'), 'hold')); break;
      case 'app-install': out.push(btn('back', t('act.back'), 'primary')); out.push(btn('install', t('act.install'), 'hold')); break;
      case 'spd': case 'epc': case 'spc': {
        if (s.invalid || f.amountRaw) { out.push(`<button class="btn btn-secondary" disabled>${I('octagon')}${t('act.blocked')}</button>`); out.push(btn('back', t('act.rescan'), 'primary')); break; }
        if (danger) { out.push(btn('back', t('act.back'), 'primary')); break; }
        out.push(`<div class="btn-row">${btn('copy-account', t('act.copyAccount'), 'secondary', 'copy')}${f.amount ? btn('copy-amount', t('act.copyAmount'), 'secondary', 'copy') : ''}</div>`);
        if (f.vs) out.push(btn('copy-vs', t('act.copyVS'), 'secondary', 'copy'));
        out.push(btn('save-qr', t('act.saveQR'), a.band === 'caution' ? 'secondary' : 'primary', 'save'));
        out.push(`<div class="hold-alt">${t('act.saveQRHint')}</div>`);
        if (a.band === 'caution') out.unshift(btn('back', t('act.back'), 'primary'));
        break;
      }
      case 'sid': out.push(btn('save-qr', t('act.saveQR'), 'primary', 'save')); break;
      case 'crypto': out.push(btn('copy-address', t('act.copyAddress'), 'secondary', 'copy')); out.push(btn('back', t('act.back'), 'primary')); break;
      case 'paybysquare': out.push(btn('close', t('act.close'), 'primary')); break;
      case 'sms':
        if (f.premium) { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('sms', t('act.holdSms'), 'hold')); }
        else out.push(btn('sms', t('act.prepareSms'), 'primary', 'message'));
        break;
      case 'tel':
        if (f.premium || f.mmi || s.consequences?.length) { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('call', t('act.holdCall'), 'hold')); }
        else out.push(btn('call', t('act.call'), 'primary', 'phone'));
        break;
      case 'mailto':
        if (a.band === 'caution' || danger) { out.push(btn('back', t('act.back'), 'primary')); out.push(btn('mail', t('act.compose'), 'secondary')); }
        else out.push(btn('mail', t('act.compose'), 'primary', 'envelope'));
        break;
      case 'contact':
        out.push(ctx.contactSaved ? `<button class="btn btn-secondary" disabled>${I('check')}${t('act.contactSaved')}</button>` : btn('add-contact', t('act.addContact'), 'primary', 'person'));
        break;
      case 'wifi':
        out.push(btn('join', t('act.join'), f.security === 'open' ? 'secondary' : 'primary', 'wifi'));
        if (f.password) out.push(btn('copy-pw', t('act.copyPw'), 'secondary', 'copy'));
        break;
      case 'event': out.push(btn('add-event', t('act.addEvent'), 'primary', 'calendar')); break;
      case 'geo': out.push(btn('maps', t('act.maps'), 'primary', 'mapPin')); break;
      case 'otpauth': out.push(btn('close', t('act.understand'), 'primary')); out.push(btn('passwords', t('act.continueHold'), 'hold')); break;
      case 'login': out.push(btn('close', t('act.understand'), 'primary')); out.push(btn('login', t('act.continueHold'), 'hold')); break;
      case 'otpauth-migration': case 'seed': case 'walletconnect': case 'hc1': out.push(btn('close', t('act.understand'), 'primary')); break;
      case 'fido': out.push(btn('close', t('act.understand'), 'primary')); break;
      case 'data-uri': case 'js-uri': case 'intent': out.push(btn('back', t('act.back'), 'primary')); out.push(btn('copy-text', t('act.copyText'), 'secondary', 'copy')); break;
      default: out.push(btn('copy-text', t('act.copyText'), 'secondary', 'copy')); out.push(btn('close', t('act.close'), 'primary'));
    }
    return `<div class="actions">${out.join('')}</div>`;
  }

  return { header, headerModel, meter, topReasons, moreReasons, weakNotes, consequenceHTML, checksHTML, completenessNotice, typeCard, actions, typeName, typeIcon, evidenceSorted, consequences };
})();
