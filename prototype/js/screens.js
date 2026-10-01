/* Phone screens. Pure-ish render functions: (state, sample) → HTML. app.js owns state and events. */
window.BQ = window.BQ || {};

BQ.screens = (function () {
  const t = (k, a) => BQ.t(k, a);
  const esc = (s) => BQ.esc(s);
  const I = (n, c) => BQ.icon(n, c);

  function shell(S) {
    return `<div class="phone" data-device="${S.device}" data-theme="${S.theme}" data-glass="${S.glass}">
      <span class="se-speaker"></span><span class="se-home"></span>
      <div class="screen" data-text="${S.text}">
        <div class="island"></div>
        <div class="statusbar" id="L-status"><span>9:41</span>${BQ.statusIcons()}</div>
        <div class="layer layer-scene" id="L-scene"></div>
        <div class="layer" id="L-scanui"></div>
        <div class="flash" id="L-flash"></div>
        <div class="dim" id="L-dim" data-action="dim"></div>
        <div class="sheet" id="L-sheet" role="dialog" aria-modal="true"></div>
        <div class="page" id="L-page"></div>
        <div class="page" id="L-page2"></div>
        <div class="safari" id="L-safari"></div>
        <div id="L-onb"></div>
        <div id="L-alert"></div>
        <div class="toast solid" id="L-toast" role="status" aria-live="polite"></div>
        <div class="confetti" id="L-confetti"></div>
        <div class="home-indicator" id="L-home"></div>
      </div>
    </div>`;
  }

  /* ───────── Scanner ───────── */
  function scanUI(S, rects, W, H) {
    const pad = 22;
    const r = rects[0] || { x: W * 0.3, y: H * 0.35, w: W * 0.4, h: W * 0.4 };
    const locked = S.frozen && S.selectedRect != null ? rects[S.selectedRect] || r : null;
    const box = locked || { x: r.x - pad, y: r.y - pad, w: r.w + pad * 2, h: r.h + pad * 2 };
    const reticle = `<div class="reticle ${locked ? 'locked' : 'idle'}" style="left:${box.x}px;top:${box.y}px;width:${box.w}px;height:${box.h}px"><i></i><i></i><i></i><i></i></div>`;
    const hits = rects.map((rc, i) => `<button class="code-hit" data-action="scan" data-rect="${i}" aria-label="${esc(t('ctl.scan'))}" style="left:${rc.x}px;top:${rc.y}px;width:${rc.w}px;height:${rc.h}px"></button>`).join('');
    const badges = S.chooser ? rects.map((rc, i) => `<span class="code-badge" style="left:${rc.x + rc.w}px;top:${rc.y}px">${i + 1}</span>`).join('') : '';
    const denied = S.cameraDenied ? `<div class="denied">${I('cameraOff')}<h3>${t('denied.title')}</h3><p>${t('denied.text')}</p>
        <button class="btn btn-primary" data-action="alert-camera-settings">${t('denied.settings')}</button><button class="btn btn-plain" style="color:#fff" data-action="gallery">${t('denied.gallery')}</button></div>` : '';
    return `${S.cameraDenied ? '' : reticle + hits + badges}
      <div class="scan-title">${t('scan.title')}</div>
      <button class="icon-btn glass scan-gallery" data-action="gallery" aria-label="${t('scan.gallery')}">${I('photo')}</button>
      ${S.cameraDenied ? '' : `<button class="glass scan-settings" data-action="open-settings">${I('gear')} ${t('scan.settings')}</button>
      <div class="glass scan-hint"><strong>${t('scan.hint')}</strong><span>${t('scan.hintSub')}</span></div>`}
      ${denied}`;
  }

  /* ───────── Sheets ───────── */
  function checking(S, sample) {
    const host = sample.fields?.hostDisplay || sample.fields?.host || '';
    const steps = S.steps.map((label, i) => {
      const st = i < S.progressStep ? 'done' : i === S.progressStep ? 'active' : '';
      const mark = st === 'done' ? `<span class="st" style="color:var(--safe)">${I('check')}</span>` : st === 'active' ? `<span class="st"><span class="spinner"></span></span>` : `<span class="st"></span>`;
      return `<li class="${st}">${mark}<span>${label}</span></li>`;
    }).join('');
    return `${chrome(false)}<div class="sheet-scroll"><div class="checking">
      ${S.style === 'mascot' ? BQ.mascot('checking', 96) : ''}
      <span class="type-chip">${I(BQ.cards.typeIcon(sample.type))} ${esc(BQ.cards.typeName(sample.type))}</span>
      <h2>${t('check.title')}</h2>
      ${host ? `<div class="target">${esc(host)}</div>` : ''}
      <div class="sub">${t('check.sub')}</div>
      <ol class="steps">${steps}</ol>
      <button class="btn btn-secondary btn-cancel" data-action="cancel-check">${t('check.cancel')}</button>
    </div></div>`;
  }

  function chrome(back, title = '') {
    return `<div class="sheet-chrome"><span class="grabber"></span>
      ${back ? `<button class="sheet-back" data-action="${back}" aria-label="${t('common.back')}">${I('chevronLeft')}</button>` : '<span></span>'}
      ${title ? `<span class="sheet-title-small">${esc(title)}</span>` : '<span></span>'}
      <button class="sheet-close" data-action="close-sheet" aria-label="${t('act.close')}">${I('x')}</button></div>`;
  }

  function stickerRelevant(S, sample, a) {
    return S.fromCamera && ['url', 'payment'].includes(sample.engine) && ['parking', 'bench', 'mall', 'poster', 'windshield'].includes(sample.scene) && ['caution', 'danger', 'incomplete'].includes(a.band);
  }

  function reportEligible(sample, a) {
    return !sample.sensitive && ['url', 'payment', 'sms', 'phone'].includes(sample.engine) && (a.band === 'danger' || a.band === 'caution');
  }
  function reportRow(S, sample, a) {
    if (!reportEligible(sample, a)) return '';
    const autoB = S.sharing.b && S.sharing.age15 && a.band === 'danger' && S.fromCamera;
    const autoA = S.sharing.a && S.sharing.age15;
    if (!autoA && !autoB) return `<button class="btn btn-plain" data-action="report-preview">${I('flag')} ${t('act.report')}</button>`;
    return `<div class="report" id="report-row">${reportInner(S, autoB)}</div>`;
  }
  function reportInner(S, withPhoto) {
    const R = S.report;
    const what = withPhoto ? t('rep.photoGps') : t('rep.dataOnly');
    if (R.state === 'manual') return `<span class="ring" style="background:var(--fill)">${I('flag')}</span><span class="txt">${t('act.report')}<small>${what}</small></span><button data-action="report-send">${t('rep.send')}</button>`;
    if (R.state === 'countdown') return `<span class="ring" style="background:conic-gradient(var(--tint) ${(R.remaining / R.total) * 360}deg, var(--fill) 0)"><span style="background:var(--card);width:22px;height:22px;border-radius:50%;display:grid;place-items:center">${R.remaining}</span></span><span class="txt">${t('rep.countdown', { n: R.remaining })}<small>${what}</small></span><button data-action="report-cancel">${t('rep.cancel')}</button>`;
    if (R.state === 'sending') return `<span class="ring"><span class="spinner"></span></span><span class="txt">${t('rep.sending')}<small>${what}</small></span>`;
    if (R.state === 'sent') return `<span class="ring" style="background:var(--safe-bg);color:var(--safe)">${I('check')}</span><span class="txt">${t('rep.sent')}<small>${what}</small></span><button data-action="report-preview">${t('rep.details')}</button>`;
    if (R.state === 'failed') return `<span class="ring" style="background:var(--incomplete-bg);color:var(--incomplete)">${I('cloudOff')}</span><span class="txt">${t('rep.failed')}<small>${what}</small></span>`;
    if (R.state === 'cancelled') return `<span class="ring" style="background:var(--fill)">${I('x')}</span><span class="txt">${t('rep.cancelled')}</span><button data-action="report-preview">${t('act.report')}</button>`;
    return '';
  }

  function result(S, sample, a) {
    const ctx = { contactSaved: S.contactSaved, revealPw: S.revealPw };
    const quickChecks = (a.band === 'safe' || a.band === 'info') && sample.checks?.length
      ? `<div class="card tight"><div class="sub-h" style="margin-top:0">${t('sec.checked')}</div>${BQ.cards.checksHTML(sample, 3)}</div>` : '';
    const raw = sample.sensitive ? `<div class="raw">${esc(BQ.pick({ cs: 'Obsah skryt — citlivý kód se nikde neukládá ani neodesílá.', en: 'Content hidden — sensitive codes are never stored or sent.' }))}</div>` : `<div class="raw">${esc(sample.payload)}</div>`;
    const m = a.math || {};
    const diag = S.senior || !a.scored ? '' : `<div class="sub-h">${t('sec.diag')}</div><div class="raw">b = ${m.baseline} · ${(m.groups || []).map((g) => `${g.group} ${g.contribution}`).join(' · ') || '—'}\nlogit ${m.logit} → ${m.raw}${m.weakOnlyCapApplied ? ` · cap ${m.weakOnlyCapApplied}` : ''}${m.floorApplied ? ` · floor ${m.floorApplied.floor}` : ''} → ${a.score}</div>`;
    return `${chrome(false)}<div class="sheet-scroll" id="result-scroll">
      ${BQ.cards.header(sample, a, S.style)}
      ${BQ.cards.meter(sample, a)}
      ${stickerRelevant(S, sample, a) ? `<div class="notice" style="background:var(--caution-bg);color:var(--caution-strong)">${I('hand')}<div>${t('scan.stickerTip')}</div></div>` : ''}
      ${BQ.cards.typeCard(sample, ctx)}
      ${BQ.cards.completenessNotice(sample, a)}
      ${BQ.cards.topReasons(sample, a)}
      ${BQ.cards.consequenceHTML(sample)}
      ${quickChecks}
      ${BQ.cards.actions(sample, a, ctx)}
      ${reportRow(S, sample, a)}
      <details class="more"><summary>${t('sec.details')} ${I('chevronRight')}</summary><div class="more-body">
        ${BQ.cards.moreReasons(sample)}${BQ.cards.weakNotes(sample, a)}
        ${sample.checks?.length ? `<div class="sub-h">${t('sec.checked')}</div>${BQ.cards.checksHTML(sample)}` : ''}
        <div class="sub-h">${t('sec.raw')}</div>${raw}${diag}
      </div></details>
    </div>`;
  }

  function preview(S, sample, a) {
    const page = sample.inspection?.page;
    const body = page
      ? `<div class="card"><div class="claim" style="margin-top:0"><em>${t('prev.claim')}</em>„${esc(page.title)}“</div>
          ${page.extract.map((line, i) => {
            if (/^\[.*\]$/.test(line.trim())) return `<div class="extract-line"><span class="extract-field">${I('hand')} ${esc(line.replace(/[[\]]/g, '').trim())}</span></div>`;
            if (/:\s*\[\s*\]$/.test(line.trim()) || /\[\s+\]/.test(line)) return `<div class="extract-line"><span class="extract-field">${I('pencil')} ${esc(line.split(':')[0])}</span></div>`;
            const hl = page.offer && page.offer.highlight?.includes(i);
            return `<div class="extract-line">${hl ? `<span class="offer-hl">${esc(line)}</span>` : esc(line)}</div>`;
          }).join('')}</div>
         ${page.asks?.length ? `<div class="sub-h">${t('prev.fields')}</div><div class="asks">${page.asks.map((k) => `<span class="chip caution">${esc(t('ask.' + k))}</span>`).join('')}</div>` : ''}`
      : `<div class="notice">${I('info')}<div>${t('prev.none')}</div></div>`;
    const open = a.band === 'danger'
      ? `<button class="btn btn-danger-plain hold" data-hold="open"><span class="hold-fill"></span>${I('hand')} ${t('act.hold')}</button>`
      : `<button class="btn btn-secondary" data-action="act" data-act="open">${t('act.openAnyway')}</button>`;
    return `${chrome('back-result', t('prev.title'))}<div class="sheet-scroll">
      <div class="notice" style="background:var(--info-bg);color:var(--info-strong)">${I('eye')}<div>${t('prev.note')}</div></div>
      ${body}
      <div class="actions"><button class="btn btn-primary" data-action="back-result">${t('common.back')}</button>${open}</div></div>`;
  }

  function chooser(S, children) {
    return `${chrome(false)}<div class="sheet-scroll"><div class="verdict v-caution"><div class="verdict-visual"><div class="verdict-badge anim-pop">${I('qr')}</div></div>
      <div class="verdict-text"><h2>${t('choose.title')}</h2><p>${t('choose.sub')}</p></div></div>
      <div class="list" style="margin-bottom:12px">${children.map((c, i) => `<button class="row" data-action="choose" data-index="${i}"><span class="code-badge" style="position:static;transform:none;flex:none">${i + 1}</span><span class="rtext">${BQ.fmt.hostHTML(c.fields.host, c.fields.registrable)}<small>${esc(BQ.pick(c.title))}</small></span>${I('chevronRight', 'chev')}</button>`).join('')}</div>
      <div class="notice" style="background:var(--caution-bg);color:var(--caution-strong)">${I('hand')}<div>${t('choose.tip')}</div></div></div>`;
  }

  function reportPreview(S, sample, a) {
    const f = sample.fields || {};
    const items = [
      ['Typ', BQ.cards.typeName(sample.type)],
      ['Pásmo / skóre', `${t('band.' + a.band)} · ${a.score ?? '—'}/100`],
      ['Signály', (sample.signals || []).map((x) => x.id).join(', ') || '—'],
      f.url ? ['Odkaz (bez tokenů)', f.url.replace(/([?&](token|code|sid|session)=)[^&]+/gi, '$1…')] : null,
      f.iban ? ['Účet', `${f.bankCode || f.country || ''} · #${(f.iban || '').slice(-4)} (klíčovaný hash)`] : null,
      f.number ? ['Číslo', f.numberDisplay] : null,
      ['Poloha', S.sharing.b && a.band === 'danger' && S.fromCamera ? 'přesná (GPS ± 12 m)' : 'přibližná (≈ 1 km)'],
      S.sharing.b && a.band === 'danger' && S.fromCamera ? ['Fotka', 'oříznutá, obličeje/SPZ/text zakryté, bez EXIF'] : null,
    ].filter(Boolean);
    const off = !(S.sharing.a || S.sharing.b);
    return `${chrome('back-result', t('rep.previewTitle'))}<div class="sheet-scroll">
      <p style="color:var(--label-2);margin:4px 4px 12px">${t('rep.previewSub')}</p>
      ${off ? `<div class="notice">${I('info')}<div>${t('rep.off')}</div></div>` : ''}
      <div class="card"><div class="sub-h" style="margin-top:0">${t('rep.fields')}</div><dl class="kv">${items.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl></div>
      <div class="consent-text" style="margin:0 6px 12px">${t('priv.retention')}</div>
      <div class="actions"><button class="btn btn-primary" data-action="report-send-once">${I('flag')} ${t('rep.send')}</button><button class="btn btn-plain" data-action="back-result">${t('alert.cancel')}</button></div></div>`;
  }

  function picker(S, items) {
    return `${chrome(false, t('picker.title'))}<div class="sheet-scroll" style="padding-left:0;padding-right:0"><div class="picker-grid">
      ${items.map((it, i) => `<button data-action="pick" data-index="${i}" aria-label="${esc(it.label)}">${it.thumb}${it.tag ? `<span>${esc(it.tag)}</span>` : ''}</button>`).join('')}
    </div></div>`;
  }

  /* ───────── Pages ───────── */
  function navbar(back, label) {
    return `<div class="navbar"><button class="nav-back" data-action="${back}">${I('chevronLeft')} ${esc(label)}</button><span></span></div>`;
  }
  function toggle(action, on, label) {
    return `<button class="toggle" role="switch" aria-checked="${on}" aria-label="${esc(label)}" data-action="${action}"></button>`;
  }
  function rowLink(action, icon, color, label, value = '') {
    return `<button class="row" data-action="${action}"><span class="ricon" style="background:${color}">${I(icon)}</span><span class="rtext">${label}</span>${value ? `<span class="rval">${esc(value)}</span>` : ''}${I('chevronRight', 'chev')}</button>`;
  }

  function settings(S) {
    const v = window.BQ_DATA.version;
    return `${navbar('close-page', t('scan.title'))}<div class="large-title">${t('set.title')}</div>
      <div class="group-h">${t('set.history')}</div><div class="group"><div class="list">
        ${rowLink('open-history', 'history', '#8e8e93', t('hist.title'), String(S.history.length))}
        <div class="row"><span class="rtext">${t('set.historyOn')}</span>${toggle('toggle-history', S.historyEnabled, t('set.historyOn'))}</div>
      </div><div class="group-f">${t('set.historyFoot')}</div></div>
      <div class="group-h">${t('set.checks')}</div><div class="group"><div class="list">
        <div class="row"><span class="rtext">${t('set.pageFetch')}<small>${t('set.pageFetchSub')}</small></span>${toggle('toggle-pagefetch', S.pageFetch, t('set.pageFetch'))}</div>
        <div class="row"><span class="rtext">${t('set.domain')}<small>${t('set.domainSub')}</small></span>${toggle('toggle-domain', S.domainChecks, t('set.domain'))}</div>
      </div></div>
      <div class="group-h">${t('set.privacy')}</div><div class="group"><div class="list">
        ${rowLink('open-privacy', 'shield', '#0a84ff', t('set.privacy'), S.sharing.a || S.sharing.b ? t('common.yes') : t('common.no'))}
      </div></div>
      <div class="group-h">${t('set.help')}</div><div class="group"><div class="list">
        ${rowLink('open-operator', 'antenna', '#34c759', t('set.operator'))}
        ${rowLink('open-recovery', 'lifebuoy', '#ff9500', t('set.recovery'))}
      </div></div>
      <div class="group-h">${t('set.about')}</div><div class="group"><div class="list">
        ${rowLink('open-about', 'heart', '#ff2d55', t('set.about'), v)}
      </div><div class="group-f" style="text-align:center;margin-top:14px">Bezpečné QR ${esc(v)} · ${t('set.licenseVal')}</div></div>`;
  }

  function history(S) {
    let body;
    if (!S.historyEnabled) body = `<div class="empty">${I('history')}<p>${t('hist.disabled')}</p></div>`;
    else if (!S.history.length) body = `<div class="empty">${I('qr')}<p>${t('hist.empty')}</p></div>`;
    else body = `<div class="group"><div class="list">${S.history.slice().reverse().map((h) => {
      const s = window.BQ_DATA.samples.find((x) => x.id === h.id);
      const mins = Math.floor((Date.now() - h.time) / 60000);
      const when = mins < 1 ? t('hist.now') : t('hist.min', { n: mins });
      const title = s.sensitive ? t('hist.redacted') : (s.fields?.host || s.fields?.domestic || s.fields?.name || s.fields?.ssid || BQ.pick(s.title));
      return `<button class="row" data-action="history-open" data-id="${esc(h.id)}"><span class="cat-dot ${h.band === 'info' ? 'info' : h.band}" style="width:12px;height:12px"></span><span class="rtext">${esc(title)}<small>${esc(BQ.cards.typeName(s.type))} · ${t('hist.checked', { time: when })}</small></span>${I('chevronRight', 'chev')}</button>`;
    }).join('')}</div></div>
    <div class="group" style="margin-top:14px"><div class="list"><button class="row" data-action="history-clear" style="color:var(--danger);justify-content:center">${t('hist.clear')}</button></div></div>`;
    return `${navbar('close-page2', t('set.title'))}<div class="large-title">${t('hist.title')}</div>${body}`;
  }

  function privacy(S) {
    const sh = S.sharing;
    const receipts = S.receipts.length ? S.receipts.map((r) => `<div class="row"><span class="rtext">${esc(r.label)}<small>${esc(r.when)}</small></span><button class="nav-back" style="padding:0 12px;color:var(--danger)" data-action="receipt-delete" data-id="${r.id}">${I('trash')}</button></div>`).join('') : `<div class="row"><span class="rtext" style="color:var(--label-2)">${t('priv.none')}</span></div>`;
    return `${navbar('close-page2', t('set.title'))}<div class="large-title">${t('priv.title')}</div>
      <div class="prose"><p>${t('priv.p1')}</p><p>${t('priv.p2')}</p><p>${t('priv.p3')}</p></div>
      <div class="group-h">${t('priv.share')}</div><div class="group"><div class="list">
        <div class="row"><span class="rtext">${t('priv.age')}</span>${toggle('toggle-age', sh.age15, t('priv.age'))}</div>
        <div class="row"><span class="rtext">${t('priv.a')}<small>${t('priv.aSub')}</small></span>${toggle('toggle-share-a', sh.a, t('priv.a'))}</div>
        <div class="row"><span class="rtext">${t('priv.b')}<small>${t('priv.bSub')}</small><span class="consent-text">${t('priv.consent')}</span></span>${toggle('toggle-share-b', sh.b, t('priv.b'))}</div>
        <div class="row"><span class="rtext">${t('priv.manual')}</span>${toggle('toggle-manual', sh.manual, t('priv.manual'))}</div>
        <div class="row"><span class="rtext">${t('priv.delay')}</span><span class="rval">${sh.delay} s</span></div>
      </div><div class="group-f">${sh.age15 ? t('priv.retention') : t('priv.ageNeeded')}</div></div>
      <div class="group-h">${t('priv.receipts')}</div><div class="group"><div class="list">${receipts}</div></div>
      <div class="group" style="margin-top:12px"><div class="list"><button class="row" data-action="receipts-clear" style="color:var(--danger);justify-content:center">${t('priv.deleteAll')}</button>
      ${rowLink('noop', 'doc', '#8e8e93', t('priv.policy'))}</div></div>`;
  }

  function operatorGuide(S) {
    const g = window.BQ_DATA.operatorGuide;
    const L = BQ.lang;
    return `${navbar('close-page2', t('set.title'))}<div class="large-title">${t('op.title')}</div>
      <div class="prose"><p>${esc(g.intro[L] || g.intro.cs)}</p></div>
      ${g.operators.map((op) => `<details class="guide-op"><summary><span>${esc(BQ.pick(op.name))}${op.verified ? '' : `<span class="unverified">${t('op.unverified')}</span>`}</span>${I('chevronRight', 'chev')}</summary><ol>${(op.steps[L] || op.steps.cs).map((st) => `<li>${esc(st)}</li>`).join('')}</ol></details>`).join('')}
      <div class="group-h">${t('op.tips')}</div><ul class="tips">${(g.tips[L] || g.tips.cs).map((x) => `<li>${esc(x)}</li>`).join('')}</ul>`;
  }

  function recovery(S) {
    const g = window.BQ_DATA.recoveryGuide;
    const L = BQ.lang;
    return `${navbar('close-page2', t('set.title'))}<div class="large-title">${esc(g.title[L] || g.title.cs)}</div>
      <div class="prose"><p>${esc(g.intro[L] || g.intro.cs)}</p></div>
      ${g.sections.map((sec) => `<details class="guide-op"><summary><span>${esc(sec.title[L] || sec.title.cs)}</span>${I('chevronRight', 'chev')}</summary><ol>${(sec.steps[L] || sec.steps.cs).map((st) => `<li>${esc(st)}</li>`).join('')}</ol></details>`).join('')}
      <ul class="tips">${(g.contacts[L] || g.contacts.cs).map((x) => `<li>${esc(x)}</li>`).join('')}</ul>`;
  }

  function about(S) {
    const v = window.BQ_DATA.version;
    return `${navbar('close-page2', t('set.title'))}<div class="large-title">${t('about.title')}</div>
      <div class="prose"><p>${t('about.text')}</p></div>
      <div class="group"><div class="list">
        <div class="row"><span class="rtext">${t('set.version')}</span><span class="rval">${esc(v)}</span></div>
        ${rowLink('noop', 'sparkles', '#5856d6', t('set.changelog'))}
        ${rowLink('noop', 'code', '#1c1c1e', t('set.source'), 'GitHub')}
        ${rowLink('noop', 'envelope', '#0a84ff', t('set.coop'), 'jakub@sejkora.cz')}
        <div class="row"><span class="rtext">${t('set.license')}</span><span class="rval">${t('set.licenseVal')}</span></div>
      </div></div>`;
  }

  /* ───────── Onboarding ───────── */
  function onboarding(S) {
    const step = S.onboardingStep;
    const dots = `<div class="dots">${[0, 1, 2].map((i) => `<i class="${i === step ? 'on' : ''}"></i>`).join('')}</div>`;
    const hero = S.style === 'mascot' ? `<div class="hero">${BQ.mascot(step === 0 ? 'safe' : step === 1 ? 'checking' : 'info', 150)}</div>`
      : `<div class="hero"><div class="shield glass">${I(step === 0 ? 'shieldCheck' : step === 1 ? 'camera' : 'users')}</div></div>`;
    let body = '';
    if (step === 0) body = `<h1>${t('onb.1.title')}</h1><p>${t('onb.1.text')}</p><ul><li>${I('shieldCheck')}${t('onb.1.b1')}</li><li>${I('lock')}${t('onb.1.b2')}</li><li>${I('banknote')}${t('onb.1.b3')}</li></ul>
      <span class="spacer"></span>${dots}<button class="btn btn-primary" data-action="onb-next">${t('onb.continue')}</button><button class="btn btn-plain" data-action="onb-skip">${t('onb.skip')}</button>`;
    if (step === 1) body = `<h1>${t('onb.2.title')}</h1><p>${t('onb.2.text')}</p>
      <span class="spacer"></span>${dots}<button class="btn btn-primary" data-action="onb-camera">${t('onb.allowCamera')}</button><button class="btn btn-plain" data-action="onb-next">${t('onb.notNow')}</button>`;
    if (step === 2) body = `<h1>${t('onb.3.title')}</h1><p>${t('onb.3.text')}</p>
      <div class="consent"><div class="row"><span class="rtext">${t('priv.age')}</span>${toggle('toggle-age', S.sharing.age15, t('priv.age'))}</div></div>
      <div class="consent"><div class="row"><span class="rtext"><b>${t('priv.a')}</b><span class="consent-text">${t('priv.aSub')}</span></span>${toggle('toggle-share-a', S.sharing.a, t('priv.a'))}</div></div>
      <div class="consent"><div class="row"><span class="rtext"><b>${t('priv.b')}</b><span class="consent-text">${t('priv.bSub')}</span></span>${toggle('toggle-share-b', S.sharing.b, t('priv.b'))}</div></div>
      <span class="spacer"></span>${dots}<button class="btn btn-primary" data-action="onb-done">${t('onb.done')}</button><button class="btn btn-plain" data-action="onb-done-none">${t('onb.notNow')}</button>`;
    return `<div class="onb"><div class="onb-bg"></div>${hero}${body}</div>`;
  }

  function alert(A) {
    if (!A) return '';
    return `<div class="ios-alert-wrap"><div class="ios-alert" role="alertdialog" aria-modal="true"><div class="a-body"><h4>${esc(A.title)}</h4>${A.text ? `<p>${esc(A.text)}</p>` : ''}</div>
      <div class="a-btns" style="${A.buttons.length > 2 ? 'flex-direction:column' : ''}">${A.buttons.map((b, i) => `<button class="${b.style || ''}" data-action="alert-btn" data-index="${i}">${esc(b.label)}</button>`).join('')}</div></div></div>`;
  }

  function safari(S, sample) {
    const f = sample.fields || {};
    const page = sample.inspection?.page;
    const url = sample.inspection?.final?.url || f.upgraded || f.url || f.fallback || '';
    let host = '';
    try { host = new URL(url).host; } catch { host = url; }
    return `<div class="s-top"><button data-action="safari-done">${t('safari.done')}</button><div class="s-addr">${I('lock')} ${esc(host)}</div><button data-action="safari-done">${I('compass')}</button></div>
      ${S.safariDanger ? `<div class="s-warn">${t('safari.warn')}</div>` : ''}
      <div class="s-body"><h1>${esc(page?.title || host)}</h1>${(page?.extract || ['…']).map((l) => `<p>${esc(l.replace(/[[\]]/g, ''))}</p>`).join('')}</div><div class="s-bottom"></div>`;
  }

  return { shell, scanUI, checking, result, preview, chooser, reportPreview, reportInner, picker, settings, history, privacy, operatorGuide, recovery, about, onboarding, alert, safari, reportEligible };
})();
