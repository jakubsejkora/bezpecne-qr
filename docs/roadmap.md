# Roadmap

Each milestone ships as a pull request with a +0.0.1 version bump and a CHANGELOG entry.

| # | Milestone | Status |
|---|---|---|
| M0 | Repository bootstrap: README with call for partners, AGPL + commercial licence, CLA, contributing guide, privacy draft | ✅ 0.0.1 |
| M1 | Interactive HTML prototype of every screen, shared rules and test corpus. **We iterate on it until the design is signed off**, including the choice between mascot and icons | ✅ 0.0.1 → iterating |
| M2 | `BQCore` Swift package: classifier, sensitivity gate, parsers (SPD/SID/EPC/Swiss/crypto/Wi‑Fi/vCard/…), validators, per-type risk engines, rules loader. `swift test` must pass on the whole corpus | next |
| M3 | iOS app shell and the first signed **TestFlight** upload (details below) | |
| M4 | Network inspection (details below) | |
| M5 | Share extension (images), onboarding, CZ/EN strings, operator guide, recovery help, accessibility pass, final visual polish | |
| M6 | V1 app candidate on TestFlight (internal testing) | |
| M7 | Opt-in Cloudflare backend. Real uploads start only after our own DPIA/LIA are complete; the signed community feed comes later | |
| later | Paste/share links and text, Lock Screen/Control Center control, landing page on bezpecneqr.cz, **Android** (Kotlin/Compose, same `shared/` rules), partner threat-intel APIs, score calibration | |

**M3 — iOS app shell:**
- camera and gallery scanning (QR, Micro QR, Aztec, DataMatrix, PDF417);
- freeze → result sheet with type cards;
- history and settings;
- the first signed TestFlight upload.

**M4 — network inspection:**
- the eligibility gate, re-run on every hop;
- `SafeFetcher`, a Network.framework HTTPS client bound to vetted IPs that stops before operator billing hosts;
- Quad9 DoH reputation and RDAP domain age;
- the "Výtah ze stránky" page extract;
- the subscription-page detector;
- the printed-text-vs-QR (OCR) check.

**Platforms:**
- iOS 18.0+.
- Liquid Glass on iOS 26+, with a material fallback on iOS 18.
- Built locally with Xcode 27 and distributed through TestFlight (internal).
- Android starts only after iOS V1 is done.
