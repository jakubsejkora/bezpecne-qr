# Changelog

All notable changes to Bezpečné QR are documented here.

- The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- Every change set bumps the version by **+0.0.1** (0.0.9 → 0.0.10) using `scripts/bump-version.sh`.
- Release notes for TestFlight and the App Store are written in Czech; this changelog is in English.

## [Unreleased]

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
