/* "Testovací arch" (printable real codes for device testing) and "Poznámky k návrhu". */
window.BQ = window.BQ || {};

BQ.docs = (function () {
  const esc = (s) => BQ.esc(s);

  function testSheet() {
    const D = window.BQ_DATA;
    const cards = D.samples.map((s) => {
      const code = BQ.codes.render(s.payload, s.symbology, { scale: 3 });
      const band = s.assessment.band;
      const risky = band === 'danger' || band === 'caution' || s.sensitive;
      return `<div class="code-card"><div class="code-img">${code ? `<img alt="${esc(s.id)}" src="${code.url}">` : '—'}</div>
        <div class="t">${esc(BQ.pick(s.title))}</div>
        <div><span class="pill ${band}">${esc(band)}${s.assessment.score != null ? ' · ' + s.assessment.score : ''}</span> <span class="pill info">${esc(s.symbology)}</span></div>
        <div class="m">${esc(s.id)}</div>
        ${risky ? `<div class="warn">⚠︎ Testovací kód — neotevírat v jiné aplikaci</div>` : ''}</div>`;
    }).join('');
    const hard = hardCases();
    return `<div class="doc">
      <h1>Testovací arch</h1>
      <p class="lead">Skutečné kódy pro všech ${D.samples.length} vzorků ze sdíleného korpusu (<code>shared/testdata/samples.json</code>) — pro pozdější testování aplikace na iPhonu (skenování z obrazovky Macu nebo z papíru). Všechny domény jsou smyšlené a v den vytvoření neexistovaly; přesto kódy označené ⚠︎ neotevírejte v jiných aplikacích. Kódy generuje knihovna bwip-js (MIT) přímo v prohlížeči.</p>
      <div class="doc-actions"><button class="ctl-btn primary" data-action="print">Vytisknout (A4)</button></div>
      <h2>Náročné případy</h2>
      <div class="sheet-grid hard-grid">${hard}</div>
      <h2>Všechny vzorky</h2>
      <div class="sheet-grid">${cards}</div>
    </div>`;
  }

  function hardCases() {
    const url = 'https://www.kavarnaulipy.cz/menu';
    const long = 'https://prihlaseni-internetove-bankovnictvi-overeni-totoznosti-klienta.sluzby-zakaznikum-podpora.xyz/cz/overeni?id=' + 'x'.repeat(120);
    const q = (p, sym = 'qr', o) => BQ.codes.render(p, sym, o)?.url;
    const card = (title, inner, cls = '') => `<div class="code-card"><div class="code-img ${cls}">${inner}</div><div class="t">${esc(title)}</div></div>`;
    return [
      card('Malý kód (tiny)', `<img class="tiny" src="${q(url, 'qr', { scale: 1 })}">`, 'tiny'),
      card('Hustý kód (dlouhá adresa)', `<img src="${q(long)}">`),
      card('Inverzní barvy', `<img src="${q(url, 'qr', { invert: true })}">`),
      card('Natočený kód', `<img src="${q(url)}">`, 'rotated'),
      card('Poškozený kód (skvrna)', `<img src="${q(url)}">`, 'damaged'),
      card('Odlesk', `<img src="${q(url)}">`, 'glare'),
      card('Dva kódy vedle sebe (nálepka)', `<div class="pair"><img src="${q('https://parking.praha.eu/PA/1234')}"><img src="${q('https://easypark-platba.cc/praha')}"></div>`),
      card('Aztec', `<img src="${q('M1NOVAKOVA/JANA       EABC123 PRGAMSKL 1352 285Y012A0025 100', 'aztec')}">`),
      card('DataMatrix', `<img src="${q(url, 'datamatrix')}">`),
      card('PDF417', `<img src="${q('Objednávka č. 2026-0815, vyzvednutí do 30. 9.', 'pdf417')}">`),
      card('Micro QR', `<img src="${q('STUL 4', 'microqr')}">`),
      card('Čeština (UTF‑8) v QR Platbě', `<img src="${q('SPD*1.0*ACC:CZ6508000000192000145399*AM:99.00*CC:CZK*MSG:Příspěvek na útulek')}">`),
    ].join('');
  }

  function notes() {
    const D = window.BQ_DATA;
    const counts = D.samples.reduce((m, s) => ((m[s.assessment.band] = (m[s.assessment.band] || 0) + 1), m), {});
    return `<div class="doc">
      <h1>Poznámky k návrhu</h1>
      <p class="lead">Prototyp ukazuje, co aplikace Bezpečné QR zobrazí po naskenování každého podporovaného typu kódu. Síťové odpovědi jsou simulované (data v korpusu), výpočet skóre je skutečný — stejná pravidla (<code>shared/rules/weights.json</code>) bude používat iOS aplikace i budoucí Android.</p>
      <div class="wall">„Nejdřív vysvětli, co se stane. Pak nabídni další krok.“</div>
      <div class="notes-grid">
        <div class="note-box"><h3>Jak prototyp používat</h3><ul>
          <li>Vlevo vyberte vzorek, pak klepněte na kód ve scéně nebo na „Simulovat sken“.</li>
          <li>Nahoře přepínejte jazyk, tmavý režim, <b>Ikony × Maskot</b>, sklo iOS 26 × iOS 18, iPhone SE, velké písmo a síť (Online / Pomalá / Offline).</li>
          <li>„Seniorský test“ skryje diagnostiku — pro testování s lidmi.</li>
          <li>Stav se ukládá do adresy (#…) — odkaz můžete poslat dál.</li>
          <li>Vpravo je diagnostika: signály, výpočet skóre, data.</li></ul></div>
        <div class="note-box"><h3>Pásma výsledku</h3><ul>
          <li><span class="pill safe">Bez známých hrozeb</span> 0–24 — nikdy „bezpečný web“ ani „ověřeno“.</li>
          <li><span class="pill caution">Buďte opatrní</span> 25–59 — vede konkrétní obava.</li>
          <li><span class="pill danger">Nebezpečné</span> 60–100 — pravděpodobný následek a co dělat.</li>
          <li><span class="pill incomplete">Nelze ověřit</span> — kontrola neúplná a důkazy nejasné.</li>
          <li><span class="pill alert">Pozor na následky</span> — kód něco udělá (přesměruje hovory, nainstaluje profil…), i když podvod neprokazujeme.</li></ul>
          <p>Korpus: ${Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(' · ')}.</p></div>
        <div class="note-box"><h3>Rozhodnutí pro vás</h3><ul>
          <li><b>Maskot „Bodlík“ × výrazné ikony</b> — přepínač nahoře.</li>
          <li>Barevnost pásem a „Pozor na následky“ (oranžová).</li>
          <li>Texty výsledků (čeština, vykání).</li>
          <li>Rozložení skeneru: galerie vpravo nahoře, „Nastavení“ vlevo dole.</li>
          <li>Co ještě chybí nebo přebývá?</li></ul></div>
        <div class="note-box"><h3>Co je simulované</h3><ul>
          <li>Kamera (ilustrované scény se skutečnými kódy), Fotky, Safari, Zprávy, Kontakty.</li>
          <li>Síťové kontroly (přesměrování, stránka, Quad9, stáří domény) — z korpusu.</li>
          <li>Hlášení týmu (backend přijde jako poslední milník V1).</li>
          <li>Tekuté sklo je CSS aproximace — skutečný vzhled ověříme v iOS 26.</li></ul></div>
        <div class="note-box"><h3>Barvy</h3><div class="swatches">
          ${[['safe', '#15914a'], ['caution', '#c46a00'], ['danger', '#d42a2a'], ['alert', '#d4570b'], ['incomplete', '#5f6b7c'], ['info', '#0a66ff'], ['Bodlík ink', '#1f3a8a']].map(([n, c]) => `<div class="swatch"><i style="background:${c}"></i><span>${n}<br>${c}</span></div>`).join('')}</div></div>
        <div class="note-box"><h3>Soukromí v prototypu</h3><ul>
          <li>Citlivé kódy (2FA, přihlašovací, obnovovací fráze, hesla Wi‑Fi, palubenky) se neukládají do historie ani nenahlašují.</li>
          <li>Hlášení: dva nezávislé souhlasy, od 15 let, fotka s maskami, 30 dní uchování.</li>
          <li>Adresa stránky v prototypu obsahuje jen ID scénáře, nikdy obsah kódu.</li></ul></div>
      </div>
    </div>`;
  }

  return { testSheet, notes };
})();
