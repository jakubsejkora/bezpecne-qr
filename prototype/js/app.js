/* Prototype controller: state, rendering, events, simulated scan flow. */
(function () {
  const D = window.BQ_DATA;
  const t = (k, a) => BQ.t(k, a);
  const esc = BQ.esc;
  const $ = (sel, root = document) => root.querySelector(sel);

  const S = {
    tab: 'prototype',
    lang: 'cs', theme: 'light', style: 'icons', glass: 'ios26', device: 'pro', text: 'normal',
    network: 'online', senior: false, cameraDenied: false,
    pageFetch: true, domainChecks: true,
    historyEnabled: true, history: [], historyGeneration: 1,
    sharing: { a: false, b: false, age15: false, delay: 10, manual: false }, locationAsked: false,
    receipts: [],
    sampleId: 'url-dcb-subscription', scenarioId: null,
    sheet: null, page: null, page2: null,
    onboarding: false, onboardingStep: 0,
    frozen: false, selectedRect: null, chooser: false, fromCamera: true,
    steps: [], progressStep: 0,
    report: { state: 'idle', remaining: 10, total: 10 },
    contactSaved: false, revealPw: false,
    safariOpen: false, safariDanger: false,
    alert: null, query: '',
  };
  const timers = new Set();
  let reportTimer = null;
  let sceneKey = '', shellKey = '';
  let rects = [];

  const later = (fn, ms) => { const id = setTimeout(() => { timers.delete(id); fn(); }, ms); timers.add(id); return id; };
  const clearTimers = () => { timers.forEach(clearTimeout); timers.clear(); };
  const dims = () => (S.device === 'se' ? { W: 375, H: 667 } : { W: 393, H: 852 });

  /* ───────── Current sample (with network toggles applied) ───────── */
  function baseSample(id = S.sampleId) { return D.samples.find((s) => s.id === id) || D.samples[0]; }
  function current() {
    const s = BQ.engine.applyNetwork(baseSample(), { network: S.network, pageFetch: S.pageFetch, domainChecks: S.domainChecks });
    return { sample: s, a: s.assessment };
  }
  function scenario() { return S.scenarioId ? D.scenarios.find((x) => x.id === S.scenarioId) : null; }

  /* ───────── URL hash state ───────── */
  const HASH_KEYS = ['lang', 'theme', 'style', 'glass', 'device', 'text', 'network'];
  function writeHash() {
    const p = new URLSearchParams();
    p.set('tab', S.tab);
    if (S.scenarioId) p.set('scenario', S.scenarioId); else p.set('s', S.sampleId);
    HASH_KEYS.forEach((k) => p.set(k, S[k]));
    if (S.senior) p.set('senior', '1');
    history.replaceState(null, '', '#' + p.toString());
  }
  function readHash() {
    const p = new URLSearchParams(location.hash.slice(1));
    if (p.get('tab')) S.tab = p.get('tab');
    if (p.get('s') && D.samples.some((s) => s.id === p.get('s'))) S.sampleId = p.get('s');
    if (p.get('scenario') && D.scenarios.some((s) => s.id === p.get('scenario'))) S.scenarioId = p.get('scenario');
    HASH_KEYS.forEach((k) => { if (p.get(k)) S[k] = p.get(k); });
    S.senior = p.get('senior') === '1';
  }

  /* ───────── Top-level render ───────── */
  function render() {
    BQ.lang = S.lang;
    document.documentElement.lang = S.lang;
    document.querySelectorAll('.tabs [data-tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === S.tab)));
    $('#view-prototype').hidden = S.tab !== 'prototype';
    $('#view-testsheet').hidden = S.tab !== 'testsheet';
    $('#view-notes').hidden = S.tab !== 'notes';
    $('#version').textContent = 'v' + D.version;
    if (S.tab === 'testsheet' && !$('#view-testsheet').dataset.done) { $('#view-testsheet').innerHTML = BQ.docs.testSheet(); $('#view-testsheet').dataset.done = '1'; }
    if (S.tab === 'notes') $('#view-notes').innerHTML = BQ.docs.notes();
    if (S.tab === 'prototype') { renderControls(); renderCatalog(); renderPhone(); renderDiagnostics(); fitPhone(); }
    writeHash();
  }

  function seg(key, label, options) {
    return `<span class="seg-wrap"><span class="seg-label">${label}</span><span class="seg" role="group" aria-label="${esc(label)}">${options.map(([v, l]) => `<button data-action="set" data-key="${key}" data-value="${v}" aria-pressed="${S[key] === v}">${l}</button>`).join('')}</span></span>`;
  }
  function renderControls() {
    $('#controls').innerHTML = [
      seg('lang', t('ctl.lang'), [['cs', 'CZ'], ['en', 'EN']]),
      seg('theme', t('ctl.theme'), [['light', t('ctl.light')], ['dark', t('ctl.dark')]]),
      seg('style', t('ctl.style'), [['icons', t('ctl.icons')], ['mascot', t('ctl.mascot')]]),
      seg('glass', t('ctl.glass'), [['ios26', 'iOS 26+'], ['ios18', 'iOS 18']]),
      seg('device', t('ctl.device'), [['pro', 'iPhone 17'], ['se', 'SE']]),
      seg('text', t('ctl.text'), [['normal', t('ctl.textNormal')], ['large', t('ctl.textLarge')]]),
      seg('network', t('ctl.net'), [['online', t('ctl.online')], ['slow', t('ctl.slow')], ['offline', t('ctl.offline')]]),
      `<button class="ctl-btn primary" data-action="scan">${t('ctl.scan')}</button>`,
      `<button class="ctl-btn" data-action="reset">${t('ctl.reset')}</button>`,
      `<button class="ctl-btn" data-action="onboarding">${t('ctl.onboarding')}</button>`,
      `<button class="ctl-btn" data-action="toggle-camera" aria-pressed="${S.cameraDenied}">${t('ctl.camera')}</button>`,
      `<button class="ctl-btn" data-action="toggle-senior" aria-pressed="${S.senior}">${t('ctl.senior')}</button>`,
    ].join('');
  }

  const GROUPS = ['links', 'payments', 'comms', 'security', 'places', 'other'];
  function renderCatalog() {
    const q = S.query.trim().toLowerCase();
    const match = (s) => !q || [s.id, BQ.pick(s.title), s.payload, s.type].join(' ').toLowerCase().includes(q);
    let html = '';
    const scen = D.scenarios.filter((x) => !q || BQ.pick(x.title).toLowerCase().includes(q));
    if (scen.length) {
      html += `<div class="cat-group"><h3>${t('group.scenarios')}<span>${scen.length}</span></h3>${scen.map((x) => `<button class="cat-item" data-action="pick-scenario" data-id="${x.id}" aria-current="${S.scenarioId === x.id}"><span class="cat-dot caution"></span>${esc(BQ.pick(x.title))}<span class="cat-tag">2×</span></button>`).join('')}</div>`;
    }
    for (const g of GROUPS) {
      const items = D.samples.filter((s) => s.group === g && match(s));
      if (!items.length) continue;
      html += `<div class="cat-group"><h3>${t('group.' + g)}<span>${items.length}</span></h3>${items.map((s) => {
        const a = BQ.engine.applyNetwork(s, { network: S.network, pageFetch: S.pageFetch, domainChecks: S.domainChecks }).assessment;
        const hm = BQ.cards.headerModel(s, a);
        const dot = hm.cls === 'v-alert' ? 'alert' : a.band;
        return `<button class="cat-item" data-action="pick" data-id="${s.id}" aria-current="${!S.scenarioId && S.sampleId === s.id}"><span class="cat-dot ${dot}"></span>${esc(BQ.pick(s.title))}${s.symbology !== 'qr' ? `<span class="cat-tag">${esc(s.symbology)}</span>` : ''}</button>`;
      }).join('')}</div>`;
    }
    $('#catalog').innerHTML = html || `<p style="padding:12px;color:#6b7384">—</p>`;
  }

  /* ───────── Phone ───────── */
  function renderPhone() {
    const key = [S.device, S.theme, S.glass, S.text].join('|');
    if (key !== shellKey) { $('#phone-wrap').innerHTML = BQ.screens.shell(S); shellKey = key; sceneKey = ''; }
    renderScene(); renderScanUI(); renderSheet(); renderPages(); renderOverlays(); renderStatus();
  }

  function renderScene() {
    const { W, H } = dims();
    const sc = scenario();
    const key = [S.scenarioId || S.sampleId, S.device].join('|');
    if (key === sceneKey) return;
    sceneKey = key;
    let built;
    if (sc) {
      const fake = baseSample(sc.children[1]); const official = baseSample(sc.children[0]);
      built = BQ.scenes.build('parking', W, H, BQ.codes.render(fake.payload, 'qr'), { second: BQ.codes.render(official.payload, 'qr') }, 'two');
    } else {
      const s = baseSample();
      const code = BQ.codes.render(s.payload, s.symbology) || BQ.codes.render('?', 'qr');
      built = BQ.scenes.build(s.scene, W, H, code, {}, s);
    }
    rects = built.rects;
    $('#L-scene').innerHTML = built.svg;
  }

  function renderScanUI() {
    const { W, H } = dims();
    $('#L-scene').classList.toggle('frozen', S.frozen);
    $('#L-scanui').innerHTML = BQ.screens.scanUI(S, rects, W, H);
  }

  function preserveScroll(el, fn) {
    const sc = el.querySelector('.sheet-scroll');
    const top = sc ? sc.scrollTop : 0;
    fn();
    const sc2 = el.querySelector('.sheet-scroll');
    if (sc2) sc2.scrollTop = top;
  }

  function renderSheet(keepScroll = false) {
    const el = $('#L-sheet');
    const dim = $('#L-dim');
    if (!S.sheet) {
      el.classList.remove('open'); dim.classList.remove('on');
      return;
    }
    const { sample, a } = current();
    let html = '';
    if (S.sheet === 'checking') html = BQ.screens.checking(S, sample);
    if (S.sheet === 'result') html = BQ.screens.result(S, sample, a);
    if (S.sheet === 'preview') html = BQ.screens.preview(S, sample, a);
    if (S.sheet === 'report') html = BQ.screens.reportPreview(S, sample, a);
    if (S.sheet === 'chooser') html = BQ.screens.chooser(S, chooserChildren());
    if (S.sheet === 'picker') html = BQ.screens.picker(S, galleryItems());
    el.classList.toggle('medium', S.sheet === 'chooser');
    const wasOpen = el.classList.contains('open');
    if (keepScroll) preserveScroll(el, () => { el.innerHTML = html; }); else el.innerHTML = html;
    dim.classList.add('on');
    if (!wasOpen) requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add('open')));
  }

  function renderPages() {
    const p1 = $('#L-page'), p2 = $('#L-page2');
    if (S.page === 'settings') { p1.innerHTML = BQ.screens.settings(S); requestAnimationFrame(() => p1.classList.add('open')); }
    else p1.classList.remove('open');
    const map = { history: BQ.screens.history, privacy: BQ.screens.privacy, operator: BQ.screens.operatorGuide, recovery: BQ.screens.recovery, about: BQ.screens.about };
    if (S.page2 && map[S.page2]) { const top = p2.scrollTop; p2.innerHTML = map[S.page2](S); p2.scrollTop = top; requestAnimationFrame(() => p2.classList.add('open')); }
    else p2.classList.remove('open');
  }

  function renderOverlays() {
    $('#L-onb').innerHTML = S.onboarding ? BQ.screens.onboarding(S) : '';
    $('#L-alert').innerHTML = BQ.screens.alert(S.alert);
    const saf = $('#L-safari');
    if (S.safariOpen) { saf.innerHTML = BQ.screens.safari(S, current().sample); requestAnimationFrame(() => saf.classList.add('open')); }
    else saf.classList.remove('open');
  }

  function renderStatus() {
    const light = !S.page && !S.page2 && !S.safariOpen && (!S.sheet || S.onboarding);
    $('#L-status').classList.toggle('dark', !light && !S.onboarding);
    $('#L-home').classList.toggle('light', (light && !S.sheet) || S.onboarding);
  }

  function fitPhone() {
    const stage = $('.stage-inner');
    const wrap = $('#phone-wrap');
    if (!stage || !wrap.firstElementChild) return;
    const phone = wrap.firstElementChild;
    const availH = stage.clientHeight - 24, availW = stage.clientWidth - 20;
    const scale = Math.min(1, availH / phone.offsetHeight, availW / phone.offsetWidth);
    wrap.style.transform = `scale(${scale})`;
  }

  /* ───────── Diagnostics ───────── */
  function renderDiagnostics() {
    const el = $('#diagnostics');
    if (S.senior) { el.innerHTML = `<div class="diag-note">${esc(t('ctl.senior'))}: diagnostika je skrytá, aby testující viděli jen to, co uvidí uživatelé.</div>`; return; }
    const sc = scenario();
    if (sc && !S.sheet) { el.innerHTML = `<h2>${esc(BQ.pick(sc.title))}</h2><div class="diag-id">${esc(sc.id)}</div><div class="diag-section"><p>Scéna se dvěma kódy (nálepka přes oficiální kód). Po skenu se ukáže výběr kódu.</p></div>`; return; }
    const { sample: s, a } = current();
    const m = a.math || {};
    const groups = (m.groups || []).map((g) => `<tr><td><code>${esc(g.group)}</code></td><td>${g.items.map((i) => `${esc(i.id)} (${i.weight})`).join('<br>')}</td><td>${g.combined}</td><td>${g.cap}</td><td><b>${g.contribution}</b></td></tr>`).join('');
    el.innerHTML = `<h2>${esc(BQ.pick(s.title))}</h2><div class="diag-id">${esc(s.id)}</div>
      <div class="diag-section"><span class="pill ${a.band}">${esc(a.band)}${a.score != null ? ' · ' + a.score + '/100' : ''}</span> <span class="pill info">${esc(s.type)}</span> <span class="pill info">engine: ${esc(s.engine)}</span> <span class="pill info">${esc(s.symbology)}</span>${s.sensitive ? ' <span class="pill alert">sensitive: ' + esc(s.sensitive) + '</span>' : ''}</div>
      ${s.whatIf ? `<div class="diag-section diag-note">Přepočítáno pro nastavení sítě (${esc(S.network)}${S.pageFetch ? '' : ', bez načtení stránky'}${S.domainChecks ? '' : ', bez kontrol domény'}). Síťové signály byly odebrány.</div>` : ''}
      <div class="diag-section"><h3>Payload</h3><pre class="diag-pre">${esc(s.payload)}</pre></div>
      <div class="diag-section"><h3>Výpočet skóre</h3>${a.scored ? `<table class="diag-table"><tr><th>skupina</th><th>signály</th><th>Σ</th><th>cap</th><th>příspěvek</th></tr>${groups || '<tr><td colspan="5">žádné signály</td></tr>'}</table>
        <p style="margin:8px 0 0">baseline ${m.baseline} → logit <b>${m.logit}</b> → 100·σ = ${m.raw}${m.weakOnlyCapApplied ? ` → strop slabých důkazů ${m.weakOnlyCapApplied}` : ''}${m.floorApplied ? ` → podlaha ${m.floorApplied.floor} (${esc(m.floorApplied.id)})` : ''} → <b>${a.score}</b></p>` : `<p>${esc(m.note || '')}</p>`}
        <p style="margin:6px 0 0">Úplnost kontroly: <b>${esc(s.completeness?.state || '—')}</b>${s.completeness?.reason ? ' · ' + esc(s.completeness.reason) : ''}</p></div>
      <div class="diag-section"><h3>Následky (mimo skóre)</h3>${(s.consequences || []).map((c) => `<div><code>${esc(c.id)}</code> · ${esc(D.signals.consequences[c.id]?.severity)}</div>`).join('') || '—'}</div>
      <div class="diag-section"><h3>Provedené kontroly</h3>${(s.checks || []).map((c) => `<div><code>${esc(c.id)}</code></div>`).join('') || '—'}</div>
      <div class="diag-section"><h3>Rozparsovaná data</h3><pre class="diag-pre">${esc(JSON.stringify(s.fields, null, 2))}</pre></div>
      ${s.inspection ? `<div class="diag-section"><h3>Simulovaná kontrola odkazu</h3><pre class="diag-pre">${esc(JSON.stringify({ chain: s.inspection.chain, domain: s.inspection.domain }, null, 2))}</pre></div>` : ''}`;
  }

  /* ───────── Scan flow ───────── */
  function resetFlow() {
    clearTimers();
    S.sheet = null; S.frozen = false; S.selectedRect = null; S.chooser = false; S.safariOpen = false; S.alert = null;
    S.contactSaved = false; S.revealPw = false;
  }

  function startScan(rectIndex = 0, fromCamera = true) {
    if (S.cameraDenied && fromCamera) return;
    clearTimers();
    S.fromCamera = fromCamera;
    S.contactSaved = false; S.revealPw = false;
    stopReport();
    if (scenario() && !S.chooser && fromCamera) {
      S.frozen = true; S.chooser = true; S.selectedRect = null; S.sheet = 'chooser';
      flash(); renderPhone(); return;
    }
    S.frozen = fromCamera; S.selectedRect = rectIndex;
    if (fromCamera) flash();
    renderScanUI();
    const { sample } = current();
    const chain = sample.inspection?.chain || [];
    const online = sample.engine === 'url' && sample.completeness?.state === 'complete' && sample.inspection && chain.length;
    if (!online) { later(showResult, fromCamera ? 420 : 250); return; }
    const steps = [chain[0]?.kind === 'shortener' ? t('check.expand') : t('check.address')];
    if (S.domainChecks) steps.push(t('check.domain'));
    const redirects = chain.filter((h) => h.status >= 300 && h.status < 400).length;
    steps.push(t('check.redirects', { n: redirects }));
    if (sample.inspection.page) steps.push(t('check.page'));
    S.steps = steps; S.progressStep = 0;
    const stepMs = S.network === 'slow' ? 1400 : 520;
    later(() => { S.sheet = 'checking'; renderSheet(); renderStatus(); }, 320);
    steps.forEach((_, i) => later(() => { S.progressStep = i + 1; if (S.sheet === 'checking') renderSheet(true); }, 320 + stepMs * (i + 1)));
    later(showResult, 320 + stepMs * (steps.length + 1) - 200);
  }

  function showResult() {
    S.sheet = 'result';
    addHistory();
    startReportIfAuto();
    renderSheet(); renderStatus(); renderDiagnostics();
  }

  function flash() {
    const f = $('#L-flash');
    if (!f) return;
    f.classList.remove('on'); void f.offsetWidth; f.classList.add('on');
  }

  function addHistory() {
    if (!S.historyEnabled) return;
    const { sample, a } = current();
    S.history = S.history.filter((h) => h.id !== sample.id);
    S.history.push({ id: sample.id, time: Date.now(), band: a.band, generation: S.historyGeneration });
  }

  const chooserChildren = () => { const sc = scenario(); return sc ? [baseSample(sc.children[1]), baseSample(sc.children[0])] : []; };

  function galleryItems() {
    const thumb = (sceneId, sampleId, extraSample) => {
      const s = sampleId ? baseSample(sampleId) : null;
      const code = s ? BQ.codes.render(s.payload, s.symbology) : BQ.codes.render('x', 'qr');
      return BQ.scenes.build(sceneId, 200, 200, code, {}, extraSample || s).svg;
    };
    return [
      { label: 'SMS', id: 'url-parcel-doplatek', thumb: thumb('screenshot', 'url-parcel-doplatek') },
      { label: 'Faktura', id: 'spd-platba-f', thumb: thumb('letter', 'spd-platba-f') },
      { label: 'Plakát', id: 'event-concert', thumb: thumb('poster', 'event-concert') },
      { label: t('picker.noCode'), noCode: true, tag: t('picker.noCode'), thumb: thumb('landscape') },
      { label: 'Wi‑Fi', id: 'wifi-wpa2', thumb: thumb('wifi', 'wifi-wpa2') },
      { label: 'Vizitka', id: 'vcard-scam-url', thumb: thumb('card', 'vcard-scam-url') },
    ];
  }

  /* ───────── Report (opt-in sharing) ───────── */
  function stopReport() { if (reportTimer) clearInterval(reportTimer); reportTimer = null; S.report = { state: 'idle', remaining: S.sharing.delay, total: S.sharing.delay }; }
  function startReportIfAuto() {
    stopReport();
    const { sample, a } = current();
    if (!BQ.screens.reportEligible(sample, a) || !S.sharing.age15 || !(S.sharing.a || S.sharing.b)) return;
    if (S.sharing.manual) { S.report.state = 'manual'; return; }
    S.report = { state: 'countdown', remaining: S.sharing.delay, total: S.sharing.delay };
    reportTimer = setInterval(() => {
      S.report.remaining -= 1;
      if (S.report.remaining <= 0) { clearInterval(reportTimer); reportTimer = null; sendReport(); return; }
      updateReportRow();
    }, 1000);
  }
  function sendReport() {
    S.report.state = 'sending'; updateReportRow();
    later(() => {
      if (S.network === 'offline') { S.report.state = 'failed'; }
      else {
        S.report.state = 'sent';
        const { sample } = current();
        S.receipts.push({ id: Math.random().toString(36).slice(2, 8), label: sample.fields?.host || BQ.cards.typeName(sample.type), when: new Date().toLocaleString(S.lang === 'cs' ? 'cs-CZ' : 'en-GB') });
        if (S.sheet !== 'result') toast(t('toast.reportSent'), 'check');
      }
      updateReportRow();
    }, 1200);
  }
  function updateReportRow() {
    const row = document.getElementById('report-row');
    if (!row) return;
    const { a } = current();
    row.innerHTML = BQ.screens.reportInner(S, S.sharing.b && a.band === 'danger' && S.fromCamera);
  }

  /* ───────── Feedback ───────── */
  let toastTimer = null;
  function toast(msg, icon = 'check') {
    const el = $('#L-toast');
    if (!el) return;
    el.innerHTML = `${BQ.icon(icon)} ${esc(msg)}`;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 1800);
  }
  function confetti() {
    const el = $('#L-confetti');
    if (!el || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const colors = ['#ff375f', '#0a84ff', '#30d158', '#ffd60a', '#bf5af2', '#ff9f0a'];
    el.innerHTML = Array.from({ length: 70 }, (_, i) => `<i style="left:${Math.random() * 100}%;background:${colors[i % colors.length]};animation-delay:${Math.random() * 0.35}s;transform:rotate(${Math.random() * 180}deg)"></i>`).join('');
    setTimeout(() => (el.innerHTML = ''), 2200);
  }
  function showAlert(title, text, buttons) { S.alert = { title, text, buttons }; renderOverlays(); }

  /* ───────── Actions from result sheets ───────── */
  function perform(act) {
    const { sample, a } = current();
    const f = sample.fields || {};
    const critical = BQ.cards.headerModel(sample, a).cls === 'v-alert';
    switch (act) {
      case 'back': case 'close': closeSheet(); break;
      case 'open':
        S.safariDanger = a.band === 'danger' || critical;
        S.safariOpen = true; renderOverlays(); renderStatus(); break;
      case 'preview': S.sheet = 'preview'; renderSheet(); break;
      case 'install': case 'subscribe': case 'login': case 'passwords': toast(t('toast.opened'), 'external'); break;
      case 'sms': toast(t('toast.sms'), 'message'); break;
      case 'call': toast(t('toast.call'), 'phone'); break;
      case 'mail': toast(t('toast.mail'), 'envelope'); break;
      case 'copy-account': case 'copy-amount': case 'copy-vs': case 'copy-pw': case 'copy-text': case 'copy-address': toast(t('toast.copied'), 'copy'); break;
      case 'save-qr': toast(t('toast.savedPhotos'), 'save'); break;
      case 'add-contact': S.contactSaved = true; renderSheet(true); confetti(); break;
      case 'join': showAlert(t('alert.wifiTitle', { ssid: f.ssid }), '', [{ label: t('alert.cancel') }, { label: t('alert.join'), style: 'bold', fn: () => toast(t('toast.joined', { ssid: f.ssid }), 'wifi') }]); break;
      case 'add-event': toast(t('toast.event'), 'calendar'); break;
      case 'maps': toast(t('toast.opened'), 'mapPin'); break;
      default:
        if (act.startsWith('confirm-')) {
          const inner = act.slice(8);
          showAlert(t('alert.openTitle'), t('alert.openText'), [{ label: t('alert.cancel'), style: 'bold' }, { label: t('alert.open'), style: 'destructive', fn: () => perform(inner) }]);
        }
    }
  }

  function closeSheet() {
    clearTimers();
    S.sheet = null; S.frozen = false; S.selectedRect = null; S.chooser = false;
    renderSheet(); renderScanUI(); renderStatus(); renderDiagnostics();
  }

  /* ───────── Hold-to-confirm ───────── */
  let hold = null;
  function holdStart(el) {
    const fill = el.querySelector('.hold-fill');
    const t0 = performance.now();
    hold = { el, raf: 0 };
    const step = (now) => {
      const p = Math.min(1, (now - t0) / 2000);
      if (fill) fill.style.transform = `scaleX(${p})`;
      if (p >= 1) { const act = el.dataset.hold; holdEnd(); perform(act); return; }
      hold.raf = requestAnimationFrame(step);
    };
    hold.raf = requestAnimationFrame(step);
  }
  function holdEnd() {
    if (!hold) return;
    cancelAnimationFrame(hold.raf);
    const fill = hold.el.querySelector('.hold-fill');
    if (fill) fill.style.transform = 'scaleX(0)';
    hold = null;
  }
  document.addEventListener('pointerdown', (e) => { const el = e.target.closest('[data-hold]'); if (el) { e.preventDefault(); holdStart(el); } });
  ['pointerup', 'pointercancel', 'pointerleave'].forEach((ev) => document.addEventListener(ev, holdEnd, true));
  document.addEventListener('keydown', (e) => { const el = e.target.closest?.('[data-hold]'); if (el && (e.key === 'Enter' || e.key === ' ') && !hold && !e.repeat) { e.preventDefault(); holdStart(el); } });
  document.addEventListener('keyup', (e) => { if (e.key === 'Enter' || e.key === ' ') holdEnd(); });

  /* ───────── Sharing toggles (with permission flow) ───────── */
  function toggleShare(which) {
    if (!S.sharing.age15) { toast(t('priv.ageNeeded'), 'info'); return; }
    const turningOn = !S.sharing[which];
    const apply = () => { S.sharing[which] = turningOn; renderPages(); renderOverlays(); };
    if (turningOn && !S.locationAsked) {
      S.locationAsked = true;
      showAlert(t('alert.locTitle'), t('alert.locText'), [{ label: t('alert.locOnce'), fn: apply }, { label: t('alert.locWhile'), style: 'bold', fn: apply }, { label: t('alert.deny'), fn: apply }]);
      return;
    }
    apply();
  }

  /* ───────── Event delegation ───────── */
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-action]');
    if (!el) return;
    const act = el.dataset.action;
    switch (act) {
      case 'tab': S.tab = el.dataset.tab; render(); break;
      case 'set': S[el.dataset.key] = el.dataset.value; if (['network'].includes(el.dataset.key)) { resetFlow(); } render(); break;
      case 'pick':
        if (S.sheet === 'picker') { pickFromGallery(Number(el.dataset.index)); break; }
        S.sampleId = el.dataset.id; S.scenarioId = null; resetFlow(); stopReport(); render();
        later(() => startScan(0, true), 750);
        break;
      case 'pick-scenario': S.scenarioId = el.dataset.id; resetFlow(); render(); later(() => startScan(0, true), 750); break;
      case 'scan': if (S.sheet && S.sheet !== 'picker') break; startScan(Number(el.dataset.rect || 0), true); break;
      case 'reset': resetFlow(); S.page = null; S.page2 = null; S.onboarding = false; stopReport(); render(); break;
      case 'onboarding': resetFlow(); S.onboarding = true; S.onboardingStep = 0; renderPhone(); break;
      case 'toggle-camera': S.cameraDenied = !S.cameraDenied; resetFlow(); render(); break;
      case 'toggle-senior': S.senior = !S.senior; render(); break;
      case 'gallery': S.sheet = 'picker'; renderSheet(); renderStatus(); break;
      case 'choose': {
        const child = chooserChildren()[Number(el.dataset.index)];
        S.sampleId = child.id; S.sheet = null; S.selectedRect = Number(el.dataset.index); S.chooser = false;
        renderSheet(); renderScanUI(); renderDiagnostics(); later(() => startScan(Number(el.dataset.index), true), 350);
        break;
      }
      case 'close-sheet': case 'dim': if (S.sheet === 'checking') { toast(t('toast.cancelled'), 'x'); } closeSheet(); break;
      case 'cancel-check': toast(t('toast.cancelled'), 'x'); closeSheet(); break;
      case 'back-result': S.sheet = 'result'; renderSheet(); break;
      case 'act': perform(el.dataset.act); break;
      case 'manual-check': toast(t('toast.manual'), 'info'); break;
      case 'toggle-pw': S.revealPw = !S.revealPw; renderSheet(true); break;
      case 'report-preview': S.sheet = 'report'; renderSheet(); break;
      case 'report-cancel': clearInterval(reportTimer); reportTimer = null; S.report.state = 'cancelled'; updateReportRow(); break;
      case 'report-send': sendReport(); break;
      case 'report-send-once': S.sheet = 'result'; renderSheet(); S.report.state = 'sending'; later(() => { sendReport(); }, 50); break;
      case 'open-settings': S.page = 'settings'; renderPages(); renderStatus(); break;
      case 'close-page': S.page = null; renderPages(); renderStatus(); break;
      case 'open-history': S.page2 = 'history'; renderPages(); break;
      case 'open-privacy': S.page2 = 'privacy'; renderPages(); break;
      case 'open-operator': S.page2 = 'operator'; renderPages(); break;
      case 'open-recovery': S.page2 = 'recovery'; renderPages(); break;
      case 'open-about': S.page2 = 'about'; renderPages(); break;
      case 'close-page2': S.page2 = null; renderPages(); break;
      case 'toggle-history': S.historyEnabled = !S.historyEnabled; renderPages(); break;
      case 'toggle-pagefetch': S.pageFetch = !S.pageFetch; renderPages(); renderCatalog(); renderDiagnostics(); break;
      case 'toggle-domain': S.domainChecks = !S.domainChecks; renderPages(); renderCatalog(); renderDiagnostics(); break;
      case 'toggle-age': S.sharing.age15 = !S.sharing.age15; if (!S.sharing.age15) { S.sharing.a = false; S.sharing.b = false; } renderPages(); renderOverlays(); break;
      case 'toggle-share-a': toggleShare('a'); break;
      case 'toggle-share-b': toggleShare('b'); break;
      case 'toggle-manual': S.sharing.manual = !S.sharing.manual; renderPages(); break;
      case 'history-open': {
        S.sampleId = el.dataset.id; S.scenarioId = null; S.page = null; S.page2 = null; resetFlow();
        renderPhone(); renderDiagnostics(); later(() => startScan(0, false), 300);
        break;
      }
      case 'history-clear': S.history = []; S.historyGeneration += 1; renderPages(); break;
      case 'receipt-delete': S.receipts = S.receipts.filter((r) => r.id !== el.dataset.id); renderPages(); toast(t('toast.copied').replace(/.*/, '✓'), 'trash'); break;
      case 'receipts-clear': S.receipts = []; renderPages(); break;
      case 'alert-btn': { const b = S.alert?.buttons[Number(el.dataset.index)]; S.alert = null; renderOverlays(); if (b && b.fn) b.fn(); break; }
      case 'alert-camera-settings': toast(t('toast.opened'), 'gear'); break;
      case 'safari-done': S.safariOpen = false; renderOverlays(); renderStatus(); break;
      case 'onb-next': S.onboardingStep = Math.min(2, S.onboardingStep + 1); renderOverlays(); break;
      case 'onb-skip': S.onboarding = false; renderOverlays(); renderStatus(); break;
      case 'onb-camera': showAlert(t('alert.camTitle'), t('alert.camText'), [{ label: t('alert.deny'), fn: () => { S.cameraDenied = true; S.onboardingStep = 2; renderOverlays(); } }, { label: t('alert.allow'), style: 'bold', fn: () => { S.cameraDenied = false; S.onboardingStep = 2; renderOverlays(); } }]); break;
      case 'onb-done': S.onboarding = false; render(); break;
      case 'onb-done-none': S.sharing.a = false; S.sharing.b = false; S.onboarding = false; render(); break;
      case 'print': window.print(); break;
      default: break;
    }
  });

  function pickFromGallery(i) {
    const item = galleryItems()[i];
    S.sheet = null; renderSheet();
    if (item.noCode) { later(() => toast(t('toast.noCode'), 'photo'), 350); return; }
    S.sampleId = item.id; S.scenarioId = null;
    renderCatalog();
    later(() => startScan(0, false), 400);
  }

  $('#search').addEventListener('input', (e) => { S.query = e.target.value; renderCatalog(); });
  window.addEventListener('resize', fitPhone);
  window.addEventListener('keydown', (e) => { if (e.key === 'Escape') { if (S.alert) { S.alert = null; renderOverlays(); } else if (S.sheet) closeSheet(); } });

  readHash();
  render();
  // Expose for debugging and automated screenshots.
  /** Jump straight to a sample's result (or another sheet) without animations. */
  function show(id, { sheet = 'result', scroll = 0, fromCamera = true } = {}) {
    document.body.classList.add('no-anim');
    resetFlow(); stopReport();
    if (D.scenarios.some((x) => x.id === id)) { S.scenarioId = id; } else { S.scenarioId = null; S.sampleId = id; }
    S.fromCamera = fromCamera;
    if (sheet === 'chooser') { S.chooser = true; S.frozen = true; }
    else if (sheet) { S.frozen = fromCamera; S.selectedRect = 0; }
    S.sheet = sheet || null;
    if (sheet === 'result') startReportIfAuto();
    render();
    requestAnimationFrame(() => { const sc = document.querySelector('#L-sheet .sheet-scroll'); if (sc) sc.scrollTop = scroll; });
    return id;
  }
  window.BQApp = { S, render, startScan, perform, current, show };
})();
