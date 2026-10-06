# Changelog

All notable changes to Bezpečné QR are documented here.

- The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- Every change set bumps the version by **+0.0.1** (0.0.9 → 0.0.10) using `scripts/bump-version.sh`.
- Release notes for TestFlight and the App Store are written in Czech; this changelog is in English.

## [Unreleased]

## [0.0.10] - 2026-10-04

### Changed
- Fixed Signal / Fade / Vivid / Bottom sheet appearance; unboxed headings, compact scanner title/Photos/torch row and centred aiming corners. Status bar hidden throughout app-owned screens.
- Native Scan / Help / Settings navigation; History inside Settings and a separated Settings tab on iOS 27. Only score-chart and capture comparisons remain in internal Settings.
- One scrollable result with inline details and page extract, native blue ordinary actions, pinned Close and existing risky confirmations; removed redundant rescan buttons.
- Camera lifecycle reconciliation, stale-callback rejection, interruption/media-reset recovery, three-second startup watchdog with one automatic restart and explicit retry.
- Cached multi-code comparison across camera/photos/share extension; stable geometry, duplicate inspection coalescing, three-worker/eight-second scene budget and conservative relative recommendations.
- Clear text-only explanation, embedded/bare-domain recognition and expandable text preview.
- History V2 migration, optional sanitized check diagnostics, version-3 inbox with V1/V2 compatibility and internal preview-before-sharing JSON export. Existing records are preserved without rechecking.
- Corrected on-demand network reachability handling and cancelled-check diagnostics. Unresolved/blocked checks remain honest; recoverable failures offer retry.
- Centred creator/version footer; internal ATYPIKA Coffee support preview with QR coupon and atypika.cz link. Public promotion awaits shop/coupon verification.

### Verification and delivery
- Internal DesignReview **0.0.10 (10)** signed and uploaded on 2026-10-04. Apple reported upload success and processing; tester availability has not been independently confirmed. App and image extension versions and signatures were verified.
- 61 core, 157 service, 51 shared UI/action/localization and 22 app/extension host tests passed. Native iOS 26.5/27 checks cover results, comparison, Photos cancellation, repeated navigation and the footer; iPhone SE at AX5 covers Close/verdict and actual history preview/native sharing. Ordinary Release builds and excludes comparison controls, export and fixtures.
- Updated roadmap, architecture, privacy and public-release checklist. Local screenshots, Czech notes and interaction recordings: `.context/rc-0.0.10/`. Archive/export logs: `ios/artifacts/0.0.10-10/`. Physical-iPhone camera/share/accessibility and iOS 18 checks remain pending.

## [0.0.9] - 2026-10-04

### Changed
- The shared risk palette now blends smoothly between green (0), yellow (25), orange (45), red (60) and deep red (100). All six charts and existing meters use the same sampler; the arc is one continuous gradient stroke and Colour bands retain their intentional gaps. Scores, verdict thresholds and actions are unchanged.
- Fade now belongs to the scanner/result container, starts behind top controls and the status area, and dissolves through the header and adjoining content without adding layout space. Native sheet/popup clipping and extension chrome are preserved.

### Added
- Independent Vivid (default) and Soft wash Fade treatments, with native previews in Design Lab and contextual quick-menu switching. The App Group choice is shared with the image extension without changing saved design, chart, aiming or capture choices.
- Internal Visible (default) / Immersive scanning/results status-bar comparison, plus an explicit Show status bar command. Other tabs and native system presentations keep their normal status area; Close, rescan, tabs and the home indicator remain available.
- Continuous colour/contrast checks, Fade render coverage and native UI checks for switching, scrolling, status restoration and large-text controls. Ordinary Release ignores both new comparison preferences.

### Delivery
- Internal DesignReview **0.0.9 (9)** was signed and uploaded on 2026-10-04. App Store Connect reported **Upload succeeded** and **Uploaded package is processing**; tester availability is not yet independently confirmed. App and image extension versions, signatures and App Group entitlements were verified.
- Core/service pipeline checks, all 50 shared UI/action/localization tests and 14 lifecycle tests passed. Native iOS 27 tests cover every presentation, both treatments, status restoration, Photos, saved choices and unchanged results. Targeted iOS 26.5 restoration and iPhone SE/AX5 controls passed. Ordinary Release excludes comparison controls and fixtures.
- Comparison screenshots, Czech review notes and a local gallery are in `.context/fade-review/`. Archive/export evidence is in `ios/artifacts/0.0.9-9/`. Physical-iPhone camera/share/VoiceOver and iOS 18 fallback verification remain pending.

## [0.0.8] - 2026-10-04

### Added
- Six independently selectable Signal score charts: Spectrum, Fine rail, Colour bands, Ticks, Dots and Arc. A native preview gallery includes a sample-score slider, incomplete-check preview and sample results; scanner/result quick menus switch charts immediately. The App Group selection also applies in the image extension.
- Internal Design Lab preview of optional sharing onboarding: a bold Signal introduction followed by separate suspicious-link reporting and content-free diagnostic choices. Both start off, and the preview supports continuing without sharing.
- Czech/English copy, accessible persistent controls and an explicit completion state explaining that no data was sent and no choice was saved.

### Scope
- Chart comparisons retain the same risk palette, thresholds, score, warnings and action policy. Incomplete scales stay neutral, unscored results have no chart, and ordinary Release ignores the experimental chart preference.
- The sharing flow is an internal design preview, not a working reporting service. Live onboarding, network behavior and permissions are unchanged; the preview is excluded from ordinary Release. No ATT or location prompt is requested.
- The proposed first reporting scope is manual suspicious-link reports plus independently optional aggregate diagnostics. Photos, location, payment reporting and automatic sending remain deferred pending the data contract and backend work.

### Delivery
- Internal DesignReview **0.0.8 (8)** was signed and uploaded on 2026-10-04. App Store Connect reported upload success and processing; tester availability has not been independently confirmed. Both hosts have version 0.0.8, build 8, valid signatures and the shared App Group entitlement.
- 13 focused UI/action/localization tests and 108 chart renders passed. Native checks cover all six live choices, saved independent selections, gallery navigation and explicit rescan on iPhone SE at AX5. Ordinary Release excludes both preview controls and the corpus. Core/service checks also passed in the upload pipeline.
- Evidence: `.context/score-review/`, `.context/sharing-review/` and `ios/artifacts/0.0.8-8/`. Physical-iPhone and iOS 18 verification remain pending.

## [0.0.7] - 2026-10-04

### Added
- Four curated Signal presets (Current, Poster, Fade, Type) with native previews and live scanner/result switching. Poster is the internal default; the image extension shares the selected header.
- Independent Popup, Bottom sheet and Full page result comparisons. Every format has a persistent rescan button and Close; details preserve the active scan. Large text and oversized popup content expand into a full-height sheet.
- Shared destination-resolution metadata distinguishes the scanned URL, the last observed response, a resolved destination and an unresolved or app-handoff outcome.
- Synthetic redirect/action/history regressions, a preset/presentation render matrix and native UI tests for switching, expanding and rescanning without swiping.

### Fixed
- Missing redirect targets, unsupported refreshes, detected script navigation, HTTP errors and exhausted walks no longer appear as completed destinations. Unvisited redirect targets are never labelled as the final page. Established danger findings remain.
- Ordinary fully inspected HTTPS links open the inspected destination directly. Incomplete, sensitive, fragment-dependent and app-handoff routes keep their existing policy and clearly labelled original-link actions.
- History titles update to resolved hostnames without changing the original recheck payload. Inbox version 2 adds an optional validated hostname and accepts version-1 entries.

### Changed
- Existing app-design, aiming-guide and capture-style preferences remain independent. Normal Release ignores experimental preset/presentation preferences and excludes comparison controls and fixtures.
- Privacy text and architecture/network documentation now describe the implemented behavior. The public-release checklist records design selection, physical-iPhone/iOS 18 verification and store materials as pending gates.

### Delivery
- Internal DesignReview **0.0.7 (7)** was signed and uploaded on 2026-10-04. App Store Connect accepted the package and reported processing; completion has not been independently confirmed. App and extension signatures, versions and App Group entitlements were verified.
- 57 core, 156 service, 45 UI/action/localization and 14 app/extension lifecycle tests passed. Native UI tests cover live comparisons on iOS 26.5/27 and rescan without swiping on iPhone SE at AX5. Screenshots, a local comparison gallery and a 27-second recording are in `.context/review-0.0.7/`.

## [0.0.6] - 2026-10-03

### Fixed
- Keep the selected native tab icon and label readable over the camera in light mode. The scanner uses dark tab-bar chrome with the system foreground; History, Help and Settings continue to follow the system appearance.

### Delivery
- Internal DesignReview **0.0.6 (6)** was signed and uploaded on 2026-10-03; App Store Connect accepted the package for processing. Core/service tests and the UI package build passed. All four tabs were checked in light/dark on iOS 26.5 and 27 simulators, including the camera preview and increased contrast.

## [0.0.5] - 2026-10-03

### Added
- Eight independent camera aiming guides with visual previews, a scanner preview, and quick switching. The guide never restricts the detector's field of view; all twelve capture styles remain available separately.
- Presentation-only result summary and a shared risk colour scale, with contrast tests across every score, action/confirmation preservation tests, and an aiming-preview lifecycle test.
- Signed internal TestFlight upload **0.0.5 (5)**, accepted by App Store Connect for processing, with updated simulator screenshots and a recording of all eight aiming guides.

### Changed
- Signal is the default in both app and image extension; explicit saved design and capture choices are preserved. Editorial, Precision and Soft Contrast remain in Design Lab.
- The scanner has one compact instruction panel, no repeated app name, and no bottom hint box.
- Signal results show the verdict, score and one leading reason immediately in a saturated gradient panel with a full-colour risk strip. Accessibility text sizes place the score first.
- Full destination domains stay visible, including ASCII IDNs. URL details, repeated findings and checks are expandable; secondary actions are under “Další možnosti.” Specialized cards and essential consequences remain visible.
- Incomplete checks retain qualified scores and neutral treatment; critical consequences keep warning prominence, and unscored codes receive no fabricated score. Existing analysis, scoring, action confirmations and sensitive-data rules are unchanged.

## [0.0.4] - 2026-10-03

### Added
- Internal native Design Lab with four app designs (Editorial, Signal, Precision, Soft Contrast), twelve independent capture visualizations, quick comparison menus, and six held replay scenes. Sample actions are simulated and never enter history.
- Native Scan / History / Help / Settings tabs, shared theme environment, and App Group preferences for the app and extension.
- Working image share extension with bounded upright decoding, single/multiple-code handling, local analysis, first-use online disclosure, cancellable eight-second inspections, details, page extracts and permitted copying.
- Versioned atomic history inbox with UUID deduplication, expiry, process locking and generation tokens; regression coverage for stale writes, sensitive imagery, orientation, cancellation and preferences.
- Release-derived `DesignReview` configuration and `scripts/testflight.sh --design-review`; comparison controls and fixtures stay out of normal Release builds.
- Signed internal TestFlight upload **0.0.4 (4)**, accepted by App Store Connect for processing; simulator screenshots and short capture recordings accompany the review build.

### Changed
- Result hierarchy puts the destination, relevant warnings and actions first; scores are secondary and redirect trails are expandable. Existing specialized cards and safety rules remain.
- Capture candidates retain IDs and image-space geometry through selection. Imported images use the same presentation model; sensitive candidates immediately discard capture imagery.
- Preferences migrate without overwriting existing choices. Clearing/disabling history invalidates pending writes from either host.
- UI render coverage includes the full corpus across all designs and all capture styles across six geometries. Physical-iPhone and iOS 18 runtime verification remain outstanding.

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
