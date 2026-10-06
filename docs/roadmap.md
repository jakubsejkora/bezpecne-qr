# Roadmap

Each milestone ships as a pull request with a +0.0.1 version bump and a CHANGELOG entry.

| # | Milestone | Status |
|---|---|---|
| M0 | Repository bootstrap: README with call for partners, AGPL + commercial licence, CLA, contributing guide, privacy draft | ✅ 0.0.1 |
| M1 | Interactive HTML prototype of every screen, shared rules and test corpus. Mascot exploration remains here; native design decisions now use the 0.0.4 iPhone comparison build | ✅ 0.0.1 → iterating |
| M2 | `BQCore` Swift package: classifier, sensitivity gate, parsers (SPD/SID/EPC/Swiss/crypto/Wi‑Fi/vCard/…), validators, per-type risk engines, rules loader. `swift test` must pass on the whole corpus | ✅ 0.0.3 |
| M3 | iOS app shell and the first signed **TestFlight** upload (details below) | ✅ 0.0.2 (skeleton, upload) + 0.0.3 (app) |
| M4 | Network inspection (details below) | ✅ 0.0.3, except the OCR check |
| M5 | Image share extension, native tabs, CZ/EN, help, accessibility and visual design | 0.0.7: four Signal presets and popup/sheet/full-page comparisons added; destination labels/actions/history aligned. Existing looks/guides/capture styles retained; physical-device validation pending |
| M6 | V1 app candidate on TestFlight (internal testing) | In progress; [public-release gates](release-checklist.md) remain open |
| M7 | Opt-in Cloudflare backend. Real uploads start only after our own DPIA/LIA are complete; the signed community feed comes later | |
| later | Paste/share links and text, Lock Screen/Control Center control, landing page on bezpecneqr.cz, **Android** (Kotlin/Compose, same `shared/` rules), partner threat-intel APIs, score calibration | |

**M3 — iOS app shell:**
- camera and gallery scanning (QR, Micro QR, Aztec, DataMatrix, PDF417);
- freeze → result sheet with type cards;
- history and settings;
- the first signed TestFlight upload. The project skeleton, automatic signing and `scripts/testflight.sh` landed early in 0.0.2, and build 0.0.2 (1) of the placeholder app was uploaded to TestFlight (setup notes in [`ios/README.md`](../ios/README.md)).

**M4 — network inspection:**
- the eligibility gate, re-run on every hop;
- `SafeFetcher`, a Network.framework HTTPS client bound to vetted IPs that stops before operator billing hosts;
- Quad9 DoH reputation and RDAP domain age;
- the "Výtah ze stránky" page extract;
- the subscription-page detector;
- the printed-text-vs-QR (OCR) check — deferred until after native design selection.

**Platforms:**
- iOS 18.0+.
- Liquid Glass on iOS 26+, with a material fallback on iOS 18.
- Built locally with Xcode 27 and distributed through TestFlight (internal).
- Android starts only after iOS V1 is done.

**0.0.4 review scope:** Editorial, Signal, Precision and Soft Contrast; twelve independent capture
visualizations; Scan / History / Help / Settings; working image share extension. Defaults are
Editorial + Camera Corners, system appearance/fonts/SF Symbols and Czech/English. Review uses
Release-derived `DesignReview` builds and `scripts/testflight.sh --design-review` (internal only).
Build **0.0.4 (4)** was signed and uploaded to App Store Connect on 2026-10-03; upload accepted,
processing completion not yet confirmed. Core, service, UI and app/extension lifecycle suites pass;
the latter ran on both iOS 26.5 and 27 simulators. Delivery evidence is recorded in `ios/README.md`.

**0.0.5 refinement:** Signal is the default without overwriting explicit preferences. The scanner
has one instruction panel. Results put the verdict and score first, with a saturated risk-colour
panel, an integrated full-colour scale, one leading reason and expandable details/actions. Eight
independent aiming guides now have visual previews; the twelve post-detection styles are unchanged.
Build **0.0.5 (5)** was accepted by App Store Connect for internal processing on 2026-10-03.
Core, service, UI and lifecycle checks passed; screenshots and the guide comparison recording
are saved in `.context/signal-review/`. Processing completion has not been confirmed.

**0.0.6 contrast fix:** the selected native tab icon and label remain readable over the scanner
camera in light and dark appearance. Build **0.0.6 (6)** was accepted by App Store Connect for
internal processing on 2026-10-03. Core/service tests and the UI package build passed; all four
tabs were visually checked on iOS 26.5 and 27 in both appearances. Evidence is saved in
`.context/tab-contrast/`. Processing completion has not been confirmed.

**0.0.7 destination and design comparison:** explicit resolution metadata separates scanned,
last-observed and resolved addresses. Ordinary fully inspected HTTPS destinations open directly;
incomplete/fragment/app-handoff routes keep their original handling. History uses resolved domains
and the version-2 inbox remains compatible with version 1. Synthetic cases cover redirects,
failed/stopped walks and dynamic navigation; the user's real short-link example can be added later.

Four Signal presets (Current, Poster, Fade, Type) and three independent presentations (Popup,
Bottom sheet, Full page) are available in Design Lab and quick menus. New internal selections use
Poster + Bottom sheet. Every result has Close and an explicit rescan control; details retain the
same check. Large text or an oversized popup expands into a full-height sheet. The image extension
keeps its system-hosted sheet and shares the header preset.

**Next decisions and checks:** select the final preset/presentation on iPhone, then set public
defaults deliberately. Normal Release ignores experimental preset/presentation preferences.
Physical camera/Photos sharing, hands-on VoiceOver, motion/transparency interaction and iOS 18
fallback remain pending. Only iOS 26.5 and 27 simulators are installed on this Mac.
Finalize the icon, store screenshots, support/privacy URLs, store metadata and privacy declarations.
The [release checklist](release-checklist.md) tracks each gate; local validation and delivery evidence
are in [ios/README.md](../ios/README.md). Privacy copy now describes current behavior rather than
planned reporting/backend work.

Build **0.0.7 (7)** was signed and uploaded internally on 2026-10-04. App Store Connect accepted the
package for processing; processing completion is not independently confirmed. Core, service,
UI/action/localization, lifecycle and native interaction suites passed. Screenshots, the comparison
gallery and a short native recording are in `.context/review-0.0.7/`.

**Explicitly later:** OCR comparison, backend/reporting, paste/share text, widgets/controls,
Android and the landing page. No new scope is required to choose the native design.


**0.0.8 internal review:** Design Lab → Sharing · onboarding preview explores a benefit-first
introduction and independent, off-by-default reports/diagnostics choices. It saves no consent,
sends nothing, requests no Apple permissions and stays outside live onboarding and ordinary Release.
The proposed initial scope excludes photos/location and automatic sending. The real service and
data contract remain M7 work; see [data collection](data-collection.md). It is included in internal
DesignReview **0.0.8 (8)**, uploaded successfully on 2026-10-04. Apple reported processing; completion
and tester availability have not been independently confirmed.

The same 0.0.8 internal review adds six independent score-chart comparisons in Signal: Spectrum,
Fine rail, Colour bands, Ticks, Dots and Arc. A preview slider, incomplete-state switch and sample
results make them easy to compare; quick menus apply them to the current result without rescanning.
The app and extension share the preference. The risk scale and scoring stay unchanged. Public
Release keeps Spectrum until a deliberate final selection.


**0.0.9 internal review:** all score charts share a continuous, smoothly interpolated risk palette.
Fade starts at the presentation's real top edge and continues behind the text/chart without an
extra spacer. Vivid and Soft wash are independent internal choices, shared with the extension.
The status-bar comparison defaults to Visible and offers Immersive scanning/results with an
explicit restore command. Native navigation and rescan controls stay available. These comparisons
do not select public defaults; choose the final treatment along with the preset/chart/presentation.
Physical-iPhone and iOS 18 fallback checks remain open in the release checklist.

Build **0.0.9 (9)** was signed and uploaded internally on 2026-10-04. App Store Connect reported
upload success and processing; tester availability is not yet independently confirmed. Shared UI,
action/localization, lifecycle and native interaction checks passed; the ordinary Release check
excludes comparisons and fixtures. Evidence and screenshots are linked from `ios/README.md`.


**0.0.10 RC consolidation:** the product direction is Signal / Fade / Vivid / Bottom sheet,
with rounded aiming corners and hidden app-owned status bars. Settings, Help, History and onboarding
use unboxed bold headings; Help cards remain. The scanner has one compact title/Photos/torch row
and a guide centred in the camera viewport. History now lives inside Settings; iOS 27 separates
Settings using the native prominent tab role, with native three-tab fallbacks on iOS 26/18.
Only score-chart and capture-style comparisons remain in internal Settings. Ordinary Release uses
explicit Spectrum / Camera Corners defaults until their final selection.

Results are one scrollable sheet with inline details, page extracts and secondary actions, native blue
ordinary actions and existing deliberate risky-action confirmations. Close stays pinned; redundant
rescan buttons are removed. Native dismissal completion gates camera restart. The camera reconciles
requested state, handles interruptions/reset, attempts one restart after three seconds without frames,
and exposes retry after failed recovery; torch turns off whenever scanning pauses.

Multi-code scenes retain occurrence geometry, share inspections for duplicates and cache results.
Local checks run immediately; eligible online work runs at most three checks at a time under one
eight-second scene deadline. Only a unique fully checked/resolved low-risk ordinary web link can be
highlighted against fully checked higher-band alternatives. No parking-operator/location guarantee
is made, and selection is always explicit. Plain text gets a direct explanation and copy action.

History schema V2 stores optional diagnostic facts, with a V3 inbox accepting V1/V2. Internal
Settings → History → Export previews the actual JSON before the native share sheet; full ordinary
saved content is included and detected secrets/protected access links are redacted. Old records are
not silently rechecked and have unavailable diagnostics. The reachability check now treats an
on-demand connection consistently with services; incomplete checks retain their honest reason.

Remaining gates: physical camera/share/accessibility testing, iOS 18, final chart/capture selection,
shop/QR-coupon validation, icon/store assets/support/privacy URLs and public submission review.
OCR/reporting/backend/widgets/Android/marketing remain deferred. No automatic data uploader or
new consent flow is introduced. Delivery evidence is tracked in ios/README.md.


Build **0.0.10 (10)** was signed and uploaded through the internal DesignReview pipeline on
2026-10-04. App Store Connect accepted it and reported processing; tester availability is not
independently confirmed. Core/service/UI/lifecycle checks and targeted native interaction/export
checks passed. Ordinary Release excludes the internal controls, export and fixtures. Evidence:
`ios/README.md`, `ios/artifacts/0.0.10-10/` and `.context/rc-0.0.10/`.
