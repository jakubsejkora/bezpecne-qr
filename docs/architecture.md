# Architecture

## Repository

```
shared/      rules (JSON), test corpus, content — the single source of truth for every platform
prototype/   interactive HTML prototype (no build step, works offline)
scripts/     data generators, reference engine (engine.mjs), banking validators, version bump
docs/        this documentation
ios/         (M2+) XcodeGen project: app, ShareExtension, Packages/{BQCore, BQServices, BQUI}
backend/     (M7) Cloudflare Worker + D1 + R2
```

## iOS (planned, M2–M6)

- **BQCore** (Swift package, pure Swift, `swift test` on the Mac): classifier, sensitivity gate, parsers, validators, per-type engines and the rules loader. Rules are copied from `shared/` into the package resources.
- **BQServices** (extension-safe):
  - `SafeFetcher`: a small Network.framework HTTP/1.1 GET client that connects only to vetted public IPs, keeps SNI and certificate validation, and applies strict budgets;
  - the DoH client (Quad9) and the RDAP client;
  - Vision barcode helpers;
  - the App Group inbox.
- **BQUI** (extension-safe): result sheet, type cards, and Liquid Glass helpers (`glassEffect` on iOS 26+, materials on iOS 18).
- **App:**
  - scanner (`AVCaptureMetadataOutput` + `AVCaptureVideoDataOutput` for the frozen frame; Vision re-run for raw bytes);
  - SwiftData history;
  - settings and onboarding;
  - the reporting queue.
- **ShareExtension:** images only in V1. It writes history through an App Group inbox.
- **No third-party SDKs.**
- **Release:** a local build → TestFlight (internal) with `xcodebuild archive` and `-exportArchive` (`destination=upload`). No CI.

## Backend (planned, M7)

- **Stack:** Cloudflare Workers, with D1 and R2 created in the EU jurisdiction.
- **Endpoints:**
  - `POST /v1/reports`: opt-in reports;
  - `POST /v1/stats`: content-free daily counters;
  - `GET|DELETE /v1/receipts/:id`: account-free access and deletion.
- **Anti-abuse:** App Attest.
- **Storage:** private. Nothing is published.
