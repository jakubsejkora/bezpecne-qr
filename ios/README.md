# Bezpečné QR — iOS

SwiftUI app for iOS 18.0+ (Liquid Glass on iOS 26+, material fallback on iOS 18) with a share extension.
Since 0.0.3 it is a working scanner: camera and photo scanning, every code type from the prototype, the link check (observed redirects, page extract, Quad9 and domain age), the risk score with reasons, the type cards and actions, local history and settings. The share extension is still a stub (see [`docs/roadmap.md`](../docs/roadmap.md)).

## Requirements

- Xcode 27 (the Liquid Glass APIs need the iOS 26 SDK or newer).
- [Mint](https://github.com/yonaskolb/Mint) (`brew install mint`). It runs the XcodeGen version pinned in `Mintfile`.

## Layout

| Path | Content |
|---|---|
| `project.yml` | XcodeGen spec — the single definition of the Xcode project |
| `Config/` | Build settings (`Shared.xcconfig` holds the team, deployment target and Swift settings) |
| `BezpecneQR/` | App target: scanner (camera, photos), scan flow, system actions, history, settings, onboarding |
| `ShareExtension/` | Share extension target (images; still a stub) |
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

The Simulator has no camera: in Debug builds, Settings → Vývojářské nástroje replays any corpus sample (with its recorded inspection, or a live network check). The corpus is copied into Debug builds only.

Tests: `swift test` in `Packages/BQCore` and `Packages/BQServices` (live network tests run with `BQ_LIVE_TESTS=1`); BQUI snapshot tests with `xcodebuild test -scheme BQUI -destination 'platform=iOS Simulator,name=iPhone 17'` in its folder. After editing `shared/rules` or `shared/content`, run `scripts/sync-core-resources.sh`; after editing `prototype/js/i18n.js`, run `node scripts/gen-ui-strings.mjs`.

Simulator builds need no signing. Device builds use automatic signing with the team in `Config/Shared.xcconfig`; outside that team, change the team and the bundle identifiers locally and don't commit them.

The placeholder icon is drawn by `scripts/make-app-icon.swift`.

## TestFlight

Everything is built and uploaded from a developer Mac. There is no CI.

```sh
scripts/testflight.sh                 # archive + upload an internal-testing-only build
scripts/testflight.sh --external      # upload a build that may later go to external testers / App Review
scripts/testflight.sh --ipa-only      # archive + export a distribution-signed .ipa, skip the upload
scripts/testflight.sh --archive-only  # sign and archive only
```

The script reserves the next number in `BUILD_NUMBER`, regenerates the project, runs `swift test` for the packages that support macOS and builds the iOS-only ones, archives the Release configuration and exports with `ExportOptions.plist`. Archives, the exported `.ipa` and logs are kept in `artifacts/<version>-<build>/` (not committed). Commit the changed `BUILD_NUMBER`.

## One-time setup

1. **Xcode account.** Xcode → Settings → Accounts, signed in with an Apple ID that may manage certificates and profiles for the team.
2. **Bundle IDs and capabilities.** Nothing to do by hand: the first archive with `-allowProvisioningUpdates` registers `cz.bezpecneqr.app` and `cz.bezpecneqr.app.share`, the App Group `group.cz.bezpecneqr.app` and the Hotspot Configuration capability, and creates the profiles.
3. **App Store Connect app record.** `xcodebuild`, `altool` and the App Store Connect API cannot create it. Either:
   - App Store Connect → Apps → **+** → New App: platform iOS, name `Bezpečné QR`, primary language Czech, bundle ID `cz.bezpecneqr.app`, SKU `bezpecneqr-ios`; or
   - Xcode → Window → Organizer → select the archive → Distribute App → TestFlight Internal Only. Xcode offers to create the record.
4. **Testers.** App Store Connect → the app → TestFlight → Internal Testing → **+**: create a group with automatic distribution and add the testers. They get a TestFlight notification for every processed build.
