# Bezpečné QR — iOS

SwiftUI app for iOS 18.0+ (Liquid Glass on iOS 26+, material fallback on iOS 18) with a share extension.
Since 0.0.3 it is a working scanner: camera and photo scanning, every code type from the prototype, the link check (observed redirects, page extract, Quad9 and domain age), the risk score with reasons, the type cards and actions, local history and settings. Version 0.0.10 consolidates Signal / Fade / Vivid, native Scan / Help / Settings tabs and one result sheet, with shared multi-code analysis and internal diagnostic export. Historical exploration notes below describe older builds; the 0.0.10 section is the current behavior.

## Requirements

- Xcode 27 (the Liquid Glass APIs need the iOS 26 SDK or newer).
- [Mint](https://github.com/yonaskolb/Mint) (`brew install mint`). It runs the XcodeGen version pinned in `Mintfile`.

## Layout

| Path | Content |
|---|---|
| `project.yml` | XcodeGen spec — the single definition of the Xcode project |
| `Config/` | Build settings (`Shared.xcconfig` holds the team, deployment target and Swift settings) |
| `BezpecneQR/` | App target: scanner (camera, photos), scan flow, system actions, history, settings, onboarding |
| `ShareExtension/` | Image share extension: bounded image decoding, in-sheet analysis and history inbox |
| `Packages/BQCore` | Pure Swift: classifier, parsers, validators, link eligibility gate, risk engine, bundled rules. `swift test` replays the whole corpus |
| `Packages/BQServices` | Network inspection: `SafeFetcher` (HTTPS GET bound to vetted public IPs), Quad9 DoH, RDAP, page extract, `LinkInspector` |
| `Packages/BQUI` | Result sheet, type cards, page extract, chooser, design tokens and UI strings (generated from the prototype) |
| `ExportOptions.plist` | Export settings for App Store Connect uploads |
| `BUILD_NUMBER` | Last build number reserved by `scripts/testflight.sh` |

`BezpecneQR.xcodeproj` and both `Info.plist` files are generated and not committed.

## Build and run

```sh
cd ios
mint run xcodegen generate
open BezpecneQR.xcodeproj        # or build from the command line:
xcodebuild -project BezpecneQR.xcodeproj -scheme BezpecneQR \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The Simulator has no camera: in Debug builds, Settings → Design Lab → Result examples replays any corpus sample (with its recorded inspection, or a live network check). The corpus is copied into Debug and internal DesignReview builds only.

Tests: `swift test` in `Packages/BQCore` and `Packages/BQServices` (live network tests run with `BQ_LIVE_TESTS=1`); BQUI snapshot tests with `xcodebuild test -scheme BQUI -destination 'platform=iOS Simulator,name=iPhone 17'` in its folder. After editing `shared/rules` or `shared/content`, run `scripts/sync-core-resources.sh`; after editing `prototype/js/i18n.js`, run `node scripts/gen-ui-strings.mjs`.

Simulator builds need no signing. Device builds use automatic signing with the team in `Config/Shared.xcconfig`; outside that team, change the team and the bundle identifiers locally and don't commit them.

The placeholder icon is drawn by `scripts/make-app-icon.swift`.

## TestFlight

Everything is built and uploaded from a developer Mac. There is no CI.

```sh
scripts/testflight.sh --design-review # internal RC with chart/capture choices and export
scripts/testflight.sh                 # archive + upload an internal-testing-only build
scripts/testflight.sh --external      # upload a build that may later go to external testers / App Review
scripts/testflight.sh --ipa-only      # archive + export a distribution-signed .ipa, skip the upload
scripts/testflight.sh --archive-only  # sign and archive only
```

The script reserves the next number in `BUILD_NUMBER`, regenerates the project, runs `swift test` for the packages that support macOS and builds the iOS-only ones, archives the selected Release-derived configuration and exports with `ExportOptions.plist`. Archives, the exported `.ipa` and logs are kept in `artifacts/<version>-<build>/` (not committed). Commit the changed `BUILD_NUMBER`.

## One-time setup

1. **Xcode account.** Xcode → Settings → Accounts, signed in with an Apple ID that may manage certificates and profiles for the team.
2. **Bundle IDs and capabilities.** Nothing to do by hand: the first archive with `-allowProvisioningUpdates` registers `cz.bezpecneqr.app` and `cz.bezpecneqr.app.share`, the App Group `group.cz.bezpecneqr.app` and the Hotspot Configuration capability, and creates the profiles.
3. **App Store Connect app record.** `xcodebuild`, `altool` and the App Store Connect API cannot create it. Either:
   - App Store Connect → Apps → **+** → New App: platform iOS, name `Bezpečné QR`, primary language Czech, bundle ID `cz.bezpecneqr.app`, SKU `bezpecneqr-ios`; or
   - Xcode → Window → Organizer → select the archive → Distribute App → TestFlight Internal Only. Xcode offers to create the record.
4. **Testers.** App Store Connect → the app → TestFlight → Internal Testing → **+**: create a group with automatic distribution and add the testers. They get a TestFlight notification for every processed build.

## Internal native design review (0.0.4)

`DesignReview` derives from Release and adds `DESIGN_REVIEW`. Upload it with
`scripts/testflight.sh --design-review`; combining it with `--external` is rejected.
Normal Release excludes the corpus, Design Lab, replay controls, and sample launch arguments.

Open **Settings → Design Lab** to select one of four app designs and one of twelve independent
capture styles (48 combinations). Both choices are in the App Group and apply in the image extension.
The scanner and result sheets also offer a quick comparison menu. Six synthetic capture scenes can
be held, replayed, and continued to the chooser/result. Sample actions are simulated; samples never
write history. The regular scan flow adds no animation delay. The original HTML mascot prototype
remains available separately.

Native tabs open on Scan. History and Help have independent navigation stacks; recovery help is
also available from dangerous results. Link results keep the destination and actions near the top,
with the full redirect trail in expandable details. Specialized payment/contact/Wi-Fi cards remain.

Image sharing accepts one image through the system Share sheet. It bounds input to 30 MiB and
100 million source pixels, downsamples to at most 3000 pixels, applies orientation, and locates
codes before presenting a numbered chooser or result. Sensitive candidates discard the image.
Local results work without online checks. First-use disclosure precedes optional network work;
checks retain the existing eight-second inspection budget. Closing cancels the provider and checks.
The extension supports details, page extract and permitted copy actions, and explains app-only actions.

Non-sensitive extension history uses an atomic, versioned App Group inbox: a cross-process lock,
generation tokens captured before work, seven-day expiry, bounded entries, validation and UUID
deduplication. Clearing/disabling history invalidates in-flight writes in both hosts. Original images
never enter history. Explicit legacy preferences migrate once; newer extension choices are retained.

Additional app/extension lifecycle tests:

```sh
cd ios
mint run xcodegen generate
xcodebuild test -project BezpecneQR.xcodeproj -scheme BezpecneQR \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'
```

BQUI tests render the corpus in all four designs, capture styles across six geometries, and key
results in Czech/English, dark mode and AX5. Rendered PNGs are in `ios/build/ui-snapshots`.
Launch review scenes with `-onboardingDone YES -BQDesign editorial -BQCaptureStyle perspectiveTrace
-BQCaptureScene tilted`; use `-BQDebugSample <corpus-id>` for result screens.

Simulator note: the installed iOS 26.5/27 barcode detector returned either an unavailable-model
error or no observations for valid QR images. Simulator builds therefore use Apple's CPU-only
Vision revision 1 (limited to its supported formats); physical-device and macOS builds keep the
modern detector and all five supported symbologies. The shared decoder's orientation tests also
run against that modern detector on macOS. Camera hardware and haptics still require an iPhone.

### Build 0.0.4 (4) delivery

The signed internal-only DesignReview archive was uploaded on 2026-10-03. App Store Connect
accepted the upload and reported processing; completion of processing was not independently
confirmed. Archive/export logs are in `ios/artifacts/0.0.4-4/`.

Verification passed: 57 BQCore tests, 148 BQServices tests, 34 BQUI tests (955 executions including
parameterized cases), and 10 app/extension lifecycle tests. The lifecycle suite passed on iOS 26.5 and 27;
the final BQUI run is `ios/build/design-tests-5.xcresult` on iOS 26.5. Debug, normal Release,
and DesignReview builds succeeded. Normal Release was checked for exclusion of review fixtures.
The corpus renders cover all four designs; capture renders cover twelve styles and six scenes.
Representative screenshots include Czech/English, light/dark, increased contrast, AX5 text,
and an iPhone SE screen size.

Screenshots and four short simulator capture recordings are in `.context/design-review/`, with
review instructions in `review-notes.txt`. No physical iPhone was connected. Real camera,
system Photos sharing, haptics, VoiceOver, Reduce Motion/Transparency interaction, and iOS 18
fallback still need device/runtime validation. Xcode could not download iOS 18.5 or 18.6.

## Signal refinement (0.0.5)

Signal is now the default in the app and image extension. An explicit saved design still wins;
the other three designs remain in Design Lab. Camera aiming and post-detection capture are
independent: **Settings → Design Lab → While aiming** offers eight visual guide previews, and
**After detection** retains the twelve capture styles. The scanner's quick menu also changes the
guide immediately. The guide never limits the camera detector's field of view.

Signal uses one scanner instruction panel and a compact result summary. The saturated verdict
panel includes the score, one leading reason, and a full-colour risk scale along its bottom edge.
At accessibility text sizes the score precedes the heading. Incomplete checks qualify the score
and mute the scale; critical consequences keep warning prominence even with a low fraud score.
Unscored codes get no numeric score or green verdict. Full destination domains, including ASCII
IDNs, stay visible. Details contain full URLs, explanations and checks; secondary actions live in
“More options,” with all existing confirmations and accessible alternatives preserved.

The shared `AimGuideStyle` preference and environment are separate from `CaptureStyle`.
`ResultSummary` and `ResultActionGroups` only arrange existing analysis and action data. The
Signal colour mapping follows the existing green/yellow/orange/red scale, aligned to the existing
25/60 band boundaries. Every score and both endpoints of the subtle surface gradient are checked
for at least 4.5:1 text contrast. No scoring, network or sensitive-data policy changed.

Internal launch fixtures: `-BQAimStyle circle -BQAimPreview YES` previews the scanner guide;
`-BQCycleAims YES` records all eight guides through the real preference and restores the original
selection on completion/cancellation. `-BQDebugOpen lab` opens Design Lab. These controls stay
excluded from ordinary Release builds, which retain saved preferences and default to Signal.

The 0.0.5 screenshots, recording and verification notes are in `.context/signal-review/`.

Build **0.0.5 (5)** was signed and uploaded internally on 2026-10-03. App Store Connect accepted
the upload and reported processing; completion of processing has not been independently confirmed.
Logs are in `ios/artifacts/0.0.5-5/`. Both app and share extension report version 0.0.5, build 5.

Verification: 57 core tests, 148 service tests, 42 UI tests (1,238 executions including parameterized
cases), and 11 app/extension lifecycle tests passed. The lifecycle suite ran on iOS 26.5 and 27;
the final UI result is `ios/build/signal-ui-delivery.xcresult` on iOS 27. Debug, DesignReview and
Release builds passed; ordinary Release was checked for absence of fixtures and review launch
controls. Native simulator screenshots cover all eight guides, six risk states, payment/IDN
examples, Czech/English, light/dark, increased contrast, iPhone SE, and AX5 text. The 16-second
guide recording changes the real shared preference and restores it afterwards.

No physical iPhone was connected, and only iOS 26.5/27 runtimes are installed. Real camera,
haptics, system Photos sharing, hands-on VoiceOver, Reduce Motion/Transparency interaction and
iOS 18 fallback remain device/runtime verification items. The overlays themselves have no idle
motion, and the result surfaces are opaque; existing motion/transparency accommodations remain.

## Tab-bar contrast fix (0.0.6)

The scanner now requests dark tab-bar chrome, and the native tab selection uses the system
foreground. The selected icon and label remain readable over the camera even when the app is
in light mode; History, Help and Settings follow their normal appearance.

Internal DesignReview **0.0.6 (6)** was signed and uploaded on 2026-10-03. App Store Connect
accepted the upload and reported processing; completion has not been independently confirmed.
Both app and share extension report version 0.0.6, build 6. Logs are in `ios/artifacts/0.0.6-6/`.
The pipeline passed core/service tests and the UI package build. All four tabs were visually
checked in light/dark on iOS 26.5 and 27 simulators, with appearance switching, the camera preview
and increased contrast. Screenshots and Czech review notes are in `.context/tab-contrast/`.
Physical-device and iOS 18 verification remain outstanding. The separate score-card and
popup/sheet comparison prototypes remain previews pending design selection.


## Clearer destinations and Signal comparisons (0.0.7)

**Settings → Design Lab** now adds **Signal · header style** (Current, Poster, Fade, Type) and
**Result presentation** (Popup summary, Bottom sheet, Full page). The scanner and every result
have the same controls in the sliders menu. New internal selections use Poster + Bottom sheet;
existing app-design, aiming and capture choices remain untouched. All four app designs, eight
idle guides and twelve capture styles remain available. The share extension shares the header
preset but keeps the system's presentation.

Popup summaries keep consequential actions in Details. Bottom sheets fit their content and expand
in place for Details. Full-page results keep Close visible. All formats keep “Scan another code”
outside the scroll area; at accessibility sizes its shorter visible label keeps the button compact
while VoiceOver retains the full action name. Large text and oversized popup content use a
full-height sheet. Switching format or opening Details preserves the result model, paused scanner,
current selection and checking task.

Destination metadata distinguishes the scanned address, last HTTP response, resolved endpoint and
unresolved/app-handoff states. Results expose the complete domain and put original/full destination
URLs and the observed trail one tap away. An ordinary, completely inspected HTTPS destination opens
directly, except fragment-dependent routes. Original-link exceptions are labelled; all risk
confirmations remain. History updates only the title to the resolved hostname and keeps the original
payload for rechecking. The version-2 inbox carries an optional validated hostname and accepts old
version-1 entries. Old History is not rechecked in the background.

Review launch arguments (Debug/DesignReview only):

```sh
-onboardingDone YES -BQDesign signal -BQSignalPreset poster -BQResultPresentation popup -BQDebugSample url-menu-shortener
-onboardingDone YES -BQDesign signal -BQSignalPreset fade -BQAimPreview YES
```

Normal Release excludes Design Lab, quick menus, sample launch arguments and the corpus, and ignores
internal preset/presentation preferences. It retains the current header and standard large sheet
until the public choice is deliberately implemented. Internal selections never become public defaults
implicitly. See the [public-release checklist](../docs/release-checklist.md).

### 0.0.7 verification

- Core: 57 tests; services: 156 tests, including redirect outcomes, opening targets and inbox migration.
- BQUI: 45 tests including action policy, localization, score contrast and render coverage. All four
  presets × three layouts × six risk states × Czech/English × light/dark are rendered, plus AX5,
  scanner and extension cases. The existing four-design corpus and twelve-style capture renders remain.
- App/extension lifecycle: 14 tests passed on iOS 26.5 and 27, including stale callbacks, cancellation,
  sensitive imagery, history invalidation and presentation coordination.
- Native UI: four interaction tests passed on iOS 26.5. Live preset/format switching also passed on iOS 27;
  all three formats passed rescan-button tests on an iPhone SE at AX5. They preserve the checked
  result across changes, expand Details and return to scanning without swiping. Screenshots cover
  Czech/English, light/dark, increased contrast, critical/unscored states, payment fields and full IDNs.
- Normal Release builds successfully and both binaries were checked for the absence of review menus,
  corpus, replay entry points and comparison launch arguments.
- The 27-second recording shows real menu interaction and result transitions on iOS 27, sped up 1.8×.
- Local logs, screenshots and comparison recording are in `.context/review-0.0.7/`;
  render output is in `ios/build/ui-snapshots/review7/`, with `.xcresult` bundles under `ios/build/`.

Physical-iPhone camera/sharing, haptics, hands-on VoiceOver and Reduce Motion/Transparency interaction
remain pending, as does iOS 18 fallback verification. Installed runtimes are iOS 26.5 and 27 only.

### Build 0.0.7 (7) delivery

Signed and uploaded through `scripts/testflight.sh --design-review` on 2026-10-04. App Store Connect
reported **Upload succeeded** and **Uploaded package is processing**. Processing completion and
availability in the testers' app have not been independently confirmed. Both the app and image
extension have version 0.0.7, build 7, valid signatures and the shared App Group entitlement. The
archive includes the internal comparison controls and corpus; the ordinary Release check excludes them.

Archive/export logs: `ios/artifacts/0.0.7-7/`. Final UI result: `ios/build/review7-bqui-final.xcresult`;
final lifecycle result: `ios/build/review7-app-delivery-2.xcresult`. Native interaction results are
`review7-ui-interaction-3.xcresult`, `review7-recording-27.xcresult` and `review7-se-ax5.xcresult`
under `ios/build/`. The screenshot gallery is `.context/review-0.0.7/comparison.html`; Czech review
notes and the recording are in the same folder. The current workspace branch was retained.


## Optional sharing onboarding preview (0.0.8)

Settings → Design Lab → Sharing · onboarding preview opens a two-step native concept: first the
benefit of helping others, then separate report/diagnostic choices. Both begin off. Choices are
view-local, discarded when closed, and never affect network work or future consent. No uploader,
ATT request or location permission is included. Live onboarding remains unchanged. The entire
preview and its launch route are compiled only in Debug/DesignReview.

Launch it with `-onboardingDone YES -BQDesign signal -BQDebugOpen sharing`. Screenshots and
verification logs are in `.context/sharing-review/`. The preview is included in the internal
0.0.8 (8) upload accepted by App Store Connect on 2026-10-04; processing completion is not confirmed. The proposed collection scope is recorded separately in
[docs/data-collection.md](../docs/data-collection.md).

Verification: the native preview tests passed in Czech/English and light/dark, including independent
off-by-default choices, skipping, closing and reset after relaunch. A Czech skip test also passed
on iPhone SE at AX5. The standard Release build succeeds and excludes the preview and review controls.
Localization generation and whitespace checks pass. This is presentation-only work; no analysis,
network service, reporting preferences or privacy permissions were changed.


### Score-chart comparisons (0.0.8)

Settings → Design Lab → Score chart adds Spectrum (existing default), Fine rail, Colour bands,
Ticks, Dots and Arc. The gallery uses one adjustable sample score and an incomplete-check toggle;
its sample-result buttons open the existing corpus without network work. The sliders menu on the
scanner/results also switches the chart, independently of the header preset and result format.
The shared App Group choice applies to Signal in both app and extension. Public Release always
uses Spectrum, ignoring internal chart choices. Scoring, thresholds and action policy do not change.

Launch the gallery with `-onboardingDone YES -BQDesign signal -BQDebugOpen scores`.
`-BQScoreChart arc` selects a chart in an internal launch fixture. Gallery controls, fixtures and
launch routes are absent from ordinary Release. The charts use opaque native shapes, no decorative
motion, a black/white marker and the same full-spectrum palette. Incomplete checks mute every chart;
unscored results omit it. The arc uses a compact height and the existing popup overflow fallback.

Screenshots and verification logs: `.context/score-review/`.

Verification: 13 focused BQUI tests passed (including action/score preservation, palette contrast,
localization, Release preference isolation and 108 score-chart renders). Native tests verify all six
quick-menu choices without changing the verdict/destination, persistent independent selections, and
Settings → Design Lab navigation. The arc’s explicit rescan control passed on iPhone SE at AX5.
Debug and ordinary Release build; both Release hosts exclude comparison controls and fixtures.
Czech/English, light/dark, all four Signal presets, endpoint/threshold scores, incomplete, critical
and unscored examples are covered by renders; image-extension layouts include AX5.

Results: `score-chart-bqui-final.xcresult`, `score-chart-gallery.xcresult`,
`score-chart-ui-final.xcresult` (live switching/rescan passed; gallery accessibility was fixed and
verified in the separate gallery run), and `score-chart-se-ax5.xcresult` under `ios/build/`.
Physical-device and iOS 18 checks remain pending.

### Build 0.0.8 (8) delivery

Signed and uploaded with `scripts/testflight.sh --design-review` on 2026-10-04. App Store Connect
reported **Upload succeeded** and **Uploaded package is processing**. Availability in TestFlight
has not been independently confirmed. Both app and image extension have version 0.0.8, build 8,
verified signatures and the shared App Group entitlement. The internal archive includes both
new preview entries; ordinary Release excludes them and the corpus. Core/service checks passed
in the pipeline. Logs: `ios/artifacts/0.0.8-8/` and `.context/score-review/testflight-upload.log`.


## Continuous Fade and colour comparisons (0.0.9)

Signal's six chart styles and the existing spectrum meters now share one smooth sampler with
anchors at 0/25/45/60/100. Band gaps still mark the actual verdict boundaries. The arc is a
single angular-gradient stroke, including padded endpoints so its rounded green cap never
crosses the gradient's wrap seam. Analysis, scores and action policy are unchanged.

Select Signal → Fade, then **Fade treatment** in Design Lab or the scanner/result quick menu.
Vivid is the default; Soft wash caps the page tint at 28% and uses a tinted dark scanner scrim.
A container-owned backdrop extends behind top chrome/status and 144 points past the measured
header text. Measurements use intrinsic height, so scrolling does not move the backdrop and
there is no extra layout spacer. Sheet/popup/extension clipping stays native. Page fades are
opaque colour blends; every point uses contrast-tested page-compatible ink. Camera text has
protected scrim coverage over bright/dark footage, with an opaque accessibility fallback.

The independent **Status bar** choice defaults to Visible. Immersive hides system status only
on Scan/results; the quick menu includes Show status bar. Tabs, Close, rescan and the home
indicator stay available. Other tabs, Photos and system action controllers retain normal
status chrome. iOS 27 uses the native status-bar toolbar placement; iOS 18–26 uses
`statusBarHidden`, scoped separately to native sheets and full-screen covers. The extension
shares Fade but does not offer or apply the status-bar preference. Ordinary Release ignores
both preferences and excludes the comparison controls/fixtures.

Internal launch arguments: `-BQSignalPreset fade -BQFadeTreatment vivid|softWash`,
`-BQStatusBar visible|immersive`. `-BQAimPreview YES -BQCameraScene bright|dark` supplies
synthetic extreme camera backgrounds without detection/network work. Existing selections
are neither migrated nor reset. Public defaults must still be chosen deliberately.

Local screenshots, comparison notes and logs: `.context/fade-review/`. Physical-iPhone
camera/share/VoiceOver and iOS 18 fallback verification remain pending.


### 0.0.9 verification and delivery

- All 50 BQUI tests passed, including action preservation, localization, continuous adjacent-score
  colours, every-score/gradient-position contrast, camera-scrim contrast and the render corpus.
  Both Fade treatments cover popup/sheet/full-page, six risk states, Czech/English, light/dark,
  compact/AX5 and extension layouts. Result: `ios/build/fade-bqui-2.xcresult`.
- All 14 app/extension lifecycle tests passed: `ios/build/fade-lifecycle.xcresult`.
- All four native iOS 27 interaction tests passed: `ios/build/fade-native-27.xcresult`.
  They exercise live treatments, all three formats, visible/immersive switching, restoration on
  History/Help/Settings/Photos, preference persistence and unchanged verdict/destination.
- Targeted iOS 26.5 status restoration after scrolling/presentation changes passed:
  `ios/build/fade-native-status.xcresult`. On iPhone SE at AX5, both treatments in popup/full-page
  keep Close and rescan reachable before/after scrolling: `ios/build/fade-small-ax5-final.xcresult`.
- Bright/dark camera extremes and increased-contrast screenshots were inspected. The opaque
  scanner branch was exercised through Increase Contrast. Hands-on VoiceOver, Reduce Motion /
  Reduce Transparency interaction and physical-device camera/sharing remain pending.
- Ordinary Release builds and both binaries exclude comparison controls; the corpus is absent.
  Localization generation and whitespace checks pass. Only iOS 26.5 and 27 runtimes are installed.

The internal pipeline signed **0.0.9 (9)** with `scripts/testflight.sh --design-review --archive-only`;
after the native checks, the same verified archive was exported/uploaded with its internal-only
ExportOptions. App Store Connect reported **Upload succeeded**, **Uploaded package is processing**
and **EXPORT SUCCEEDED** on 2026-10-04. Processing completion/tester availability is not independently
confirmed. Both hosts' version/build, signatures and shared App Group entitlement were verified.
Core/service tests also passed in the pipeline. Logs and the signed archive: `ios/artifacts/0.0.9-9/`.

Screenshots: `.context/fade-review/comparison.html`, `result-comparison.png`,
`scanner-comparison.png`, `charts-cs.png` and the `extension/` and `small-ax5/` folders.
Czech review notes: `.context/fade-review/review-notes-cs.md`. The current branch is unchanged.


## Focused RC (0.0.10) — current behavior

Signal / Fade / Vivid / Bottom sheet / rounded aiming corners are now product constants,
including the image extension. Retired design preferences are preserved but ignored. Only
score-chart and after-detection capture styles remain in internal Settings → Appearance testing.
Ordinary Release always uses Spectrum / Camera Corners and excludes fixtures, comparison controls
and diagnostic export. App-owned status bars are hidden; system Photos, permissions and extension
chrome retain iOS behavior.

Scan / Help / Settings use one native tab container, with History inside Settings and the prominent
Settings role on iOS 27. Root headings are unboxed; Help cards remain. The scanner puts the brand,
Photos and available torch in one compact row, with the guide centred independently of header height.
One scrollable result sheet keeps Close pinned, expands details/extracts/actions inline and uses native
blue styling for ordinary actions. Existing hold/confirmation gates are unchanged.

Camera state is explicitly reconciled on its serial queue. Interruption, media reset, foreground and
presentation transitions reject stale work. A visible authorized camera without frames for three seconds
gets one automatic restart, then a retry control. Torch turns off when paused. Photos dismissal gates
preview restart; import generation tokens prevent stale provider results from replacing newer scans.

A shared cached multi-code session refines frozen images, retains occurrence geometry, inspects each
duplicate payload once and runs at most three online checks under one eight-second scene budget.
Only a uniquely low-risk, fully checked/resolved ordinary URL can be highlighted against fully checked
higher-band alternatives. This does not establish the correct parking operator or location. Selection
is explicit; All codes returns to the cached chooser. Only selected eligible results enter History.
Any sensitive candidate discards captured imagery. Pure text has a readable, expandable preview and
Copy; embedded/bare-domain links are identified without claiming they were inspected.

History migrates to schema V2 without deleting V1 records. Optional check diagnostics record bounded
stage timings, categorical failures and sanitized redirect facts. Inbox V3 accepts V1/V2 and retains
expiry, generation and deduplication. Internal Settings → History → Export history previews the actual
versioned JSON before native sharing. Saved ordinary content is included; secrets/protected links and
revealing labels are redacted. Legacy diagnostics are explicitly unavailable. Temporary files are
removed after sharing/cancellation; clearing History invalidates pending exports. Nothing is sent
automatically. Creator/coffee/coupon copy is complete in internal builds; public promotional copy
remains gated on shop/coupon verification.

### 0.0.10 verification

- 61 core and 157 service tests passed, including text parsing, conservative recommendation rules,
  diagnostic sanitization, redirect handling and inbox V1/V2/V3 compatibility.
- All 51 BQUI tests passed: actions, localization, palette/contrast, result/capture corpus and large
  text renders. Result: `ios/build/rc-ui-final.xcresult`.
- All 22 app/extension host tests passed on iOS 26.5 and 27, including cached selection, bounded
  concurrency/deadline, camera watchdog/recovery, migration, export redaction and cleanup. Final
  source run: `ios/build/rc-host-final.xcresult`.
- Ten native iOS 27 interaction tests passed (`rc-native-27.xcresult`); five targeted native iOS 26.5
  cases passed (`rc-native-26-final.xcresult`). They cover six result states, inline details, risky
  confirmations, multi-code selection/back, Photos cancellation, persistent choices and navigation.
- iPhone SE at AX5 keeps verdict/Close accessible and passes repeated native tab transitions. The
  history export test previews an actual saved note, opens native sharing and cancels back successfully
  (`rc-export-se-3.xcresult`). Its earlier failures were off-screen test queries; scrolling fixed the
  test without changing the product. Large-text/navigation evidence is in `rc-small-export.xcresult`.
- Ordinary Release builds successfully and excludes review menus, export, fixtures and the sample
  corpus. Localization generation and whitespace checks pass.

Screenshots, the navigation recording and a local review gallery are in `.context/rc-0.0.10/`.
All `.xcresult` bundles above are under `ios/build/`. Simulator checks do not establish physical
camera focus/performance, haptics, real Photos extension handoff or hands-on VoiceOver behavior.
Physical-iPhone camera/share/accessibility checks and iOS 18 fallback remain pending; only iOS 26.5
and 27 runtimes are available. The user's failing short URL remains an open regression input.


### Build 0.0.10 (10) delivery

Signed and uploaded internally with `scripts/testflight.sh --design-review` on 2026-10-04.
App Store Connect reported **Upload succeeded**, **Uploaded package is processing** and
**EXPORT SUCCEEDED**. Processing completion and availability in testers' TestFlight apps have
not been independently confirmed. App and share extension versions/builds are 0.0.10 (10);
the archived app and nested extension passed strict signature verification, and both shared App Group entitlements were verified. The branch was retained.

The pipeline re-ran core/service tests, built shared UI and successfully archived DesignReview.
Logs and signed archive: `ios/artifacts/0.0.10-10/`; combined upload log:
`.context/rc-0.0.10/testflight.log`. The gallery is `.context/rc-0.0.10/index.html`, with
Czech review/release notes and short native navigation recordings in the same folder. Final
iOS 27 tab transitions passed after the explicit destination-based tab appearance change
(`ios/build/rc-navigation-final.xcresult`). Public submission and the remaining checklist gates
are separate work.
