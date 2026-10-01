# Bezpečné QR — iOS

SwiftUI app for iOS 18.0+ (Liquid Glass on iOS 26+, material fallback on iOS 18) with a share extension.
At version 0.0.2 this is a **skeleton**: a placeholder screen and a stub extension that prove the project, signing and TestFlight pipeline. The scanner arrives in later versions (see [`docs/roadmap.md`](../docs/roadmap.md)).

## Requirements

- Xcode 27 (the Liquid Glass APIs need the iOS 26 SDK or newer).
- [Mint](https://github.com/yonaskolb/Mint) (`brew install mint`). It runs the XcodeGen version pinned in `Mintfile`.

## Layout

| Path | Content |
|---|---|
| `project.yml` | XcodeGen spec — the single definition of the Xcode project |
| `Config/` | Build settings (`Shared.xcconfig` holds the team, deployment target and Swift settings) |
| `BezpecneQR/` | App target: sources, assets, entitlements, privacy manifest |
| `ShareExtension/` | Share extension target (images) |
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

The script reserves the next number in `BUILD_NUMBER`, regenerates the project, runs `swift test` for every package in `Packages/`, archives the Release configuration and exports with `ExportOptions.plist`. Archives, the exported `.ipa` and logs are kept in `artifacts/<version>-<build>/` (not committed). Commit the changed `BUILD_NUMBER`.

## One-time setup

1. **Xcode account.** Xcode → Settings → Accounts, signed in with an Apple ID that may manage certificates and profiles for the team.
2. **Bundle IDs and capabilities.** Nothing to do by hand: the first archive with `-allowProvisioningUpdates` registers `cz.bezpecneqr.app` and `cz.bezpecneqr.app.share`, the App Group `group.cz.bezpecneqr.app` and the Hotspot Configuration capability, and creates the profiles.
3. **App Store Connect app record.** `xcodebuild`, `altool` and the App Store Connect API cannot create it. Either:
   - App Store Connect → Apps → **+** → New App: platform iOS, name `Bezpečné QR`, primary language Czech, bundle ID `cz.bezpecneqr.app`, SKU `bezpecneqr-ios`; or
   - Xcode → Window → Organizer → select the archive → Distribute App → TestFlight Internal Only. Xcode offers to create the record.
4. **Testers.** App Store Connect → the app → TestFlight → Internal Testing → **+**: create a group with automatic distribution and add the testers. They get a TestFlight notification for every processed build.
