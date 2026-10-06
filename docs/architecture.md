# Architecture

## Repository

```
shared/      rules (JSON), test corpus, content — the single source of truth for every platform
prototype/   interactive HTML prototype (no build step, works offline)
scripts/     data generators, reference engine (engine.mjs), banking validators, version bump
docs/        this documentation
ios/         XcodeGen project: native scanner, image ShareExtension, Packages/{BQCore, BQServices, BQUI}
backend/     (M7) Cloudflare Worker + D1 + R2
```

## iOS (implemented through 0.0.10; internal RC)

- **BQCore** (Swift package, pure Swift, `swift test` on the Mac): classifier, sensitivity gate, parsers, validators, per-type engines and the rules loader. Rules are copied from `shared/` into the package resources.
- **BQServices** (extension-safe):
  - `SafeFetcher`: a small Network.framework HTTP/1.1 GET client that connects only to vetted public IPs, keeps SNI and certificate validation, and applies strict budgets;
  - the DoH client (Quad9) and the RDAP client;
  - Vision barcode helpers;
  - the App Group inbox.
- **BQUI** (extension-safe): one result model and action policy, inline details/page extracts, type cards, shared risk palette, capture geometry and Liquid Glass helpers (`glassEffect` on iOS 26+, materials on iOS 18).
- **App:**
  - scanner (`AVCaptureMetadataOutput` + `AVCaptureVideoDataOutput` for the frozen frame; Vision refinement before choosing single/multiple presentation);
  - serialized camera lifecycle with desired-state reconciliation, interruption/reset handling, stale-callback rejection and a bounded no-frame recovery attempt;
  - SwiftData V2 history with a lightweight V1 migration and optional sanitized diagnostics;
  - one persistent native Scan / Help / Settings tab container, with History inside Settings and a prominent Settings tab on iOS 27;
  - one scrollable native result sheet, pinned Close and inline disclosures; preview resumes after dismissal completes, with scene detection cooldown independent of live frames;
  - no reporting queue or backend integration.
- **SharedUI:** the fixed Signal / Fade / Vivid theme, bounded image-provider loading, and a cached multi-code analysis session used by both hosts. Duplicate payloads share one inspection but retain marker identities. Up to three workers share an eight-second scene budget; selection never rechecks a cached result. Relative recommendations require a unique, fully resolved low-risk ordinary link with every alternative fully checked in a higher risk band. The user always chooses.
- **ShareExtension:** accepts one image, downsamples and decodes locally, and uses the same cached comparison and result UI in its system-hosted sheet. Cancellation stops loading/checks; any sensitive candidate discards captured imagery. Only explicitly selected, eligible results enter the history inbox.
- **Destination metadata:** `DestinationResolution` keeps scanned, last-observed and resolved endpoints separate from inspection completeness. The UI, action target and History derive from this shared model. Only a fully inspected ordinary HTTPS destination without fragment dependence opts into direct opening.
- **History inbox:** atomic App Group entries, cross-process locking, generation tokens, seven-day expiry and UUID deduplication. Version 3 adds optional check diagnostics; versions 1 and 2 remain readable. Resolved hostnames remain optional and original payloads are kept for explicit rechecking. Clearing/disabling history invalidates pending work. No image or sensitive payload is persisted.
- **Diagnostics/export:** completion and destination outcomes, bounded stage timings, categorical transport errors, HTTP status, sanitized redirect hosts and finding IDs; no raw headers, images or persistent device identifiers. Internal History export previews actual versioned JSON, rechecks sensitive/protected content, labels missing legacy diagnostics, and uses a temporary file with native sharing and cleanup. Nothing is uploaded automatically.
- **Internal review:** Release-derived `DesignReview` keeps only six score-chart and twelve capture-style choices in Settings, with fixtures/replay for verification. Appearance is fixed to Signal / Fade / Vivid / Bottom sheet / rounded aiming corners; app-owned status bars are hidden. Normal Release excludes controls/fixtures/export and ignores comparison preferences, using explicit Spectrum / Camera Corners defaults. Retired preferences are left intact but no longer control the app.
- **No third-party SDKs.**
- **Release:** a local build → TestFlight (internal) with `scripts/testflight.sh --design-review` (`xcodebuild archive` and `-exportArchive`, `destination=upload`). No CI. See [`ios/README.md`](../ios/README.md) and the [public-release checklist](release-checklist.md).

## Backend (planned, M7)

- **Stack:** Cloudflare Workers, with D1 and R2 created in the EU jurisdiction.
- **Endpoints:**
  - `POST /v1/reports`: opt-in reports;
  - `POST /v1/stats`: content-free daily counters;
  - `GET|DELETE /v1/receipts/:id`: account-free access and deletion.
- **Anti-abuse:** App Attest.
- **Storage:** private. Nothing is published.
