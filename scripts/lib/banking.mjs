// Reference implementations of the banking validators used by Bezpečné QR.
// The Swift (BQCore) and Kotlin ports must produce identical results; the shared
// test corpus (shared/testdata/samples.json) is validated against these functions.

/** ISO 13616 mod-97 check. Accepts IBAN with or without spaces. */
export function isValidIBAN(iban) {
  const s = String(iban).replace(/\s+/g, '').toUpperCase();
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(s)) return false;
  return mod97(s.slice(4) + s.slice(0, 4)) === 1;
}

function mod97(str) {
  let rem = 0;
  for (const ch of str) {
    const code = ch >= 'A' && ch <= 'Z' ? String(ch.charCodeAt(0) - 55) : ch;
    for (const d of code) rem = (rem * 10 + Number(d)) % 97;
  }
  return rem;
}

/** Czech domestic account check (Vyhláška 169/2011 Sb.), weights applied left→right on padded parts. */
const PREFIX_WEIGHTS = [10, 5, 8, 4, 2, 1];
const BASE_WEIGHTS = [6, 3, 7, 9, 10, 5, 8, 4, 2, 1];

export function isValidCzechAccount(prefix, number) {
  const p = String(prefix || '0').padStart(6, '0');
  const n = String(number).padStart(10, '0');
  if (!/^\d{6}$/.test(p) || !/^\d{10}$/.test(n)) return false;
  if (n.replace(/^0+/, '').length < 2) return false;
  if ((n.match(/[1-9]/g) || []).length < 2) return false;
  const sum = (digits, weights) => [...digits].reduce((acc, d, i) => acc + Number(d) * weights[i], 0);
  return sum(p, PREFIX_WEIGHTS) % 11 === 0 && sum(n, BASE_WEIGHTS) % 11 === 0;
}

/** CZ IBAN → { prefix, number, bankCode, domestic }. Returns null for non-CZ or malformed IBANs. */
export function czIBANToDomestic(iban) {
  const s = String(iban).replace(/\s+/g, '').toUpperCase();
  if (!/^CZ\d{22}$/.test(s)) return null;
  const bankCode = s.slice(4, 8);
  const prefix = s.slice(8, 14).replace(/^0+/, '');
  const number = s.slice(14).replace(/^0+/, '');
  return { prefix, number, bankCode, domestic: `${prefix ? prefix + '-' : ''}${number}/${bankCode}` };
}

/** Domestic account → CZ IBAN (with computed check digits). */
export function domesticToCzIBAN(prefix, number, bankCode) {
  const bban = String(bankCode).padStart(4, '0') + String(prefix || '0').padStart(6, '0') + String(number).padStart(10, '0');
  const check = 98 - mod97(bban + 'CZ00');
  return `CZ${String(check).padStart(2, '0')}${bban}`;
}

/** Group an IBAN in blocks of four for display. */
export function formatIBAN(iban) {
  return String(iban).replace(/\s+/g, '').replace(/(.{4})/g, '$1 ').trim();
}

/** CRC32 (IEEE 802.3), as used by the SPD/SID CRC32 field and PAY by square. */
export function crc32(str) {
  let c, crc = 0xffffffff;
  const bytes = new TextEncoder().encode(str);
  for (const b of bytes) {
    c = (crc ^ b) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return ((crc ^ 0xffffffff) >>> 0).toString(16).toUpperCase().padStart(8, '0');
}

/** IČO check digit: weights 8..2 over the first 7 digits. */
export function isValidICO(ico) {
  const s = String(ico).padStart(8, '0');
  if (!/^\d{8}$/.test(s)) return false;
  const sum = [...s.slice(0, 7)].reduce((acc, d, i) => acc + Number(d) * (8 - i), 0);
  const check = (11 - (sum % 11)) % 10;
  return check === Number(s[7]);
}
