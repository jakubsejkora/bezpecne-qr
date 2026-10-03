# Changelog

All notable changes to Bezpečné QR are documented here.

- The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- Every change set bumps the version by **+0.0.1** (0.0.9 → 0.0.10) using `scripts/bump-version.sh`.
- Release notes for TestFlight and the App Store are written in Czech; this changelog is in English.

## [Unreleased]

## [0.0.3] - 2026-10-03

### Added
- **The scanner works.** The TestFlight build is now the real app instead of the placeholder:
  - live camera scanning of QR, Micro QR, Aztec, DataMatrix and PDF417 (freeze, outline, haptic), codes from Photos, and a chooser when several codes are in view;
  - the scan → "Kontroluji…" → verdict flow with the native result sheet (verdict, risk score, type card, reasons, consequences, checks, actions, check details), page extract ("Výtah ze stránky") and hold-to-confirm for risky actions;
  - actions: in-app Safari, copy (passwords expire from the clipboard), call, prepared SMS, e-mail, add contact, add event, join Wi‑Fi, open in Maps, save a payment QR to Photos, hand 2FA codes to the system;
  - local history in Settings (sensitive codes stored as a redacted summary only), settings for history and both internet checks, the operator-protection and "Už jsem zadal(a) údaje" guides, About, a short onboarding;
  - a Debug-only menu (and launch arguments) that replays the test corpus in the Simulator.
- **`BQCore`** (Swift package): classifier and parsers for every code type in the corpus, banking validators, the link eligibility gate, the risk engine ported from `scripts/lib/engine.mjs`, bundled rules. `swift test` replays all 80 corpus samples (type, fields, evidence, consequences, completeness, band) plus false-positive guards for legitimate Czech sites.
- **`BQServices`** (Swift package): `SafeFetcher` (HTTPS-only GET bound to vetted public IPs, strict HTTP/1.1 parser, bounded gzip/deflate/brotli decoding), the redirect walk that re-runs the gate on every hop and stops before operator/carrier-billing hosts, Quad9 DoH, RDAP domain age and the page analyzer (asks, recurring offers, brand claims).
- **`BQUI`** (Swift package): the result experience ported from the prototype (all type cards, light/dark, Dynamic Type up to AX5, VoiceOver), UI strings generated from `prototype/js/i18n.js` by `scripts/gen-ui-strings.mjs`, snapshot tests for every sample.
- `scripts/sync-core-resources.sh` copies `shared/rules` and `shared/content` into BQCore (a test fails when they differ).

### Changed
- Corpus corrections found by the native engine: two missing "young domain" signals, a missing "false official" signal and a lost accent in a bitcoin label.
- Rules: legacy official government domains for the gov brand, free-hosting provider names, a word boundary in the subscription interval pattern, new `inc.*` reasons for the link checker.
- Risk engine details are documented in `docs/risk-engine.md` (implementation notes).

### Security
- An independent review of the link checker and its gate (Codex, three rounds) found 16 issues in round 1 and further edge cases in rounds 2 and 3. Examples: trailing-dot, percent-encoded and bracketed hosts slipping past the billing stop; tokens hidden in nested or multiply encoded parameters; NAT64 and special-purpose IPv6 ranges; unvetted RDAP redirects and certificate-issuer downloads; multi-member gzip; stalled or oversized pages reported as complete; a crash on malformed nested parameters. All were fixed with tests before build 3; round 3 ended at "ship after fixes" and those fixes are in.
- The link checker connects only to vetted public IPv4 addresses (the system handles NAT64), never contacts mobile-operator or carrier-billing hosts, and sends a name to Quad9/RDAP only after it resolved to public addresses.

## [0.0.2] - 2026-10-02

### Added
- **iOS project skeleton** (`ios/`), with no scanner yet:
  - XcodeGen spec (`project.yml`, XcodeGen pinned through Mint) for the app `cz.bezpecneqr.app` and the share extension `cz.bezpecneqr.app.share`: iOS 18.0+, iPhone only, Swift 6 with strict concurrency;
  - placeholder screen with the Liquid Glass helper (`glassEffect` on iOS 26+, material fallback on iOS 18) and a stub share extension for images;
  - entitlements (Hotspot Configuration, shared App Group), privacy manifests for both bundles and a placeholder app icon drawn by `scripts/make-app-icon.swift`;
  - build and one-time setup guide (`ios/README.md`).
- **TestFlight pipeline:** `scripts/testflight.sh` archives, signs and uploads from the Mac, with build numbers in `ios/BUILD_NUMBER`. `--ipa-only` and `--archive-only` stop before the upload; `--external` uploads a build that may leave internal testing. Build 0.0.2 (1) of the placeholder app is the first upload.

### Changed
- `scripts/bump-version.sh` also updates the version shown in the README.
- README, roadmap and architecture notes describe the iOS skeleton.

## [0.0.1] - 2026-09-29

### Added
- **Repository bootstrap:**
  - bilingual README (CZ/EN) with a call for partners;
  - AGPL-3.0 license, commercial-licensing note and Contributor License Agreement;
  - contributing guide and privacy-policy draft.
- **Interactive HTML prototype** (`prototype/`) of every planned app screen:
  - scanner with the gallery button top-right and Settings bottom-left;
  - freeze, then "Kontroluji…", then the result sheet;
  - type-specific result cards for 30+ code types;
  - isolated page extract, two-code "sticker" chooser, onboarding, settings, history, privacy and sharing, operator-protection guide, "I already entered my details" help;
  - opt-in reporting flow with a cancel window.
  - **Toggles:** CZ/EN, light/dark, bold icons vs the "Bodlík" hedgehog mascot, iOS 26 Liquid Glass vs iOS 18 fallback, iPhone SE, large text, online/slow/offline, camera denied, senior test mode.
  - **"Testovací arch":** a printable test sheet with real QR, Micro QR, Aztec, DataMatrix and PDF417 codes (bwip-js, MIT) plus hard cases.
- **Shared rules** (`shared/rules/`), used by the prototype now and by iOS/Android later:
  - scoring weights (per-type log-odds with capped evidence groups and floors);
  - bilingual signal texts;
  - abused TLDs, Czech brands and official domains, official parking hosts per city;
  - URL shorteners, free hosting, carrier-billing patterns;
  - Czech premium-rate SMS/voice rules, wangiri prefixes, state-authority (ČNB 0710) rule;
  - ČNB bank codes.
- **Test corpus** (`shared/testdata/samples.json`): 80 synthetic samples across all supported code types, validated against the reference engine.
- **Content** (`shared/content/`): operator payment-blocking guide and recovery guide (CZ/EN).
- **Scripts:**
  - `gen-rules.mjs` (ČNB bank codes);
  - `gen-prototype-data.mjs` (validates corpus and rules);
  - `lib/engine.mjs` (reference scorer);
  - `lib/banking.mjs` (IBAN mod-97, Czech mod-11, CRC32, IČO);
  - `bump-version.sh`.
- **Docs:** architecture, risk engine, data collection and roadmap.
