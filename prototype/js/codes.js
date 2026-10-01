/* Real 2D codes rendered in-page with bwip-js (MIT). Used by scenes and the test sheet. */
window.BQ = window.BQ || {};

BQ.codes = (function () {
  const cache = new Map();
  const BCID = { qr: 'qrcode', microqr: 'microqrcode', aztec: 'azteccode', datamatrix: 'datamatrix', pdf417: 'pdf417' };

  function render(payload, symbology = 'qr', { scale = 4, invert = false } = {}) {
    const key = `${symbology}|${scale}|${invert}|${payload}`;
    if (cache.has(key)) return cache.get(key);
    const canvas = document.createElement('canvas');
    const opts = { bcid: BCID[symbology] || 'qrcode', text: payload, scale, paddingwidth: 2, paddingheight: 2, backgroundcolor: invert ? '000000' : 'FFFFFF', barcolor: invert ? 'FFFFFF' : '000000' };
    if (symbology === 'qr') opts.eclevel = 'M';
    if (symbology === 'pdf417') { opts.columns = 4; opts.rowmult = 3; }
    let url = null;
    try {
      window.bwipjs.toCanvas(canvas, opts);
      url = canvas.toDataURL('image/png');
    } catch (e) {
      console.warn('[BQ] code render failed', symbology, e && e.message);
    }
    const result = url ? { url, w: canvas.width, h: canvas.height } : null;
    cache.set(key, result);
    return result;
  }

  return { render };
})();
