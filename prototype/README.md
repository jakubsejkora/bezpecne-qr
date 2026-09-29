# Interactive prototype

A clickable design prototype of the Bezpečné QR iOS app. It covers every supported code type and every result screen.

**Open `index.html` in a browser.** There is no build step and no network; everything, including the barcode generator, is local.

## How to use it
- **Left:** the catalogue of 80 samples (links, payments, SMS/phone/contacts, security and devices, calendar and places, other symbologies) plus a two-code "sticker" scenario. Click one; the scanner scans it automatically. You can also click the code in the scene or use **Simulovat sken**.
- **Top:** toggles.
  - language CZ/EN, light/dark theme;
  - **bold icons vs the "Bodlík" hedgehog mascot**;
  - iOS 26 Liquid Glass vs iOS 18 fallback;
  - iPhone 17 vs SE, large text;
  - network online/slow/offline, which recomputes link results live;
  - camera denied, onboarding, **senior test mode** (hides diagnostics).
- **Right:** diagnostics with the payload, score math, signals, consequences, checks and parsed fields.
- **Testovací arch:** printable real codes (QR, Micro QR, Aztec, DataMatrix, PDF417) plus hard cases, for testing the iOS app later.
- **Poznámky k návrhu:** design notes and open decisions.

The URL hash keeps the current scenario and toggles, so you can share a link to a specific state. It never contains code payloads.

## Data
`data/data.js` is generated from `shared/` by:

```
node scripts/gen-prototype-data.mjs
```

The generator validates every sample against the reference engine and fails if a result disagrees with its expected band.

Network responses (redirects, page content, Quad9, domain age) are simulated from the corpus. The scoring is real.

Third-party code: [bwip-js](https://github.com/metafloor/bwip-js) (MIT), in `vendor/bwip-js/`.
