# Public-release checklist

0.0.10 is an **internal DesignReview build**, not a public-release approval. This checklist separates implemented behavior from checks that still require a person, device or store configuration.

## Implemented and covered by automated checks

- [x] Shared URL resolution, honest unresolved labels, inspected-destination opening and original-route exceptions.
- [x] Synthetic redirects, relative targets, loops, timeouts, disabled checks, script navigation, HTTP errors, protected destinations, fragments and store handoffs.
- [x] Resolved History titles, original recheck payloads, version-1/2/3 inbox import, deduplication, expiry and invalidation of late writes.
- [x] One scrollable bottom sheet with pinned Close, inline details/extract/actions, native blue ordinary actions and preserved risky confirmations. Closing waits for native dismissal before restarting detection.
- [x] Fixed Signal / Fade / Vivid appearance, unboxed headings, centred rounded aiming guide and hidden status bar on app-owned screens. Only chart/capture comparisons remain in internal Settings.
- [x] Scan / Help / Settings navigation; History inside Settings. Native prominent Settings tab on iOS 27, three native tabs on iOS 26/18.
- [x] Cached multi-code analysis, at most three simultaneous checks within a shared eight-second scene budget; conservative relative recommendations and explicit selection.
- [x] Camera session reconciliation, interruption/reset handling, bounded startup recovery, torch lifecycle and detection cooldown for the whole captured scene.
- [x] History V2 migration, optional inert diagnostics, backward-compatible inbox V3 and preview-before-sharing internal JSON export. Secrets/protected links are redacted again at export time.
- [x] Czech/English strings, preset/presentation/risk-state renders, contrast calculations and preservation of risky-action confirmations.
- [x] Core, service, UI/action/localization and app/extension lifecycle regression suites. Verification details and local evidence paths are in [ios/README.md](../ios/README.md).
- [x] Current privacy copy describes optional website/Quad9/RDAP requests, local history, transient images and the absence of a reporting backend. [PRIVACY.md](../PRIVACY.md) is the source for the final published policy.

## Decisions before the public build

- [ ] Select the public Signal score chart after the 0.0.8 comparisons; ordinary Release ignores the internal chart preference and keeps Spectrum.
- [x] Finalize Signal / Fade / Vivid / Bottom sheet / rounded aiming guide in source, ignoring retired exploration preferences in every build.
- [x] Hide status bar on all app-owned screens. System-owned chrome remains controlled by iOS.
- [ ] Select final after-detection capture style; ordinary Release explicitly uses Camera Corners until selected.
- [x] Keep comparison controls, diagnostic export and sample fixtures outside ordinary Release.
- [ ] Verify atypika.cz shop and QR coupon before enabling the promotional footer in ordinary Release (internal builds include the requested preview).
- [ ] Add the user's real failing short URL as a regression when supplied. Current coverage uses synthetic cases; that missing example is not blocking internal delivery.

## Physical-device and fallback verification — pending

- [ ] Real iPhone camera: focus, tilted/small/edge/crowded codes, repeated scans, full-frame detection, rotation, torch, interruptions, first-frame recovery and scene cooldown.
- [ ] Real system Photos sharing: one/multiple/no codes, first-use network disclosure, closing during decode/checks, and app/extension History synchronization.
- [ ] Physical iPhone on the available supported OS releases; haptics and camera permission recovery.
- [ ] Hands-on VoiceOver order, announcements, confirmation alternatives and actions in Czech/English.
- [ ] Reduce Motion / Reduce Transparency interaction, increased contrast and maximum text size on a physical device.
- [ ] iOS 18 runtime/device fallback. Only iOS 26.5 and 27 simulators are installed on the development Mac; iOS 18 and a physical iPhone are unavailable for this delivery.

Simulator renders and UI tests are useful evidence but do not close these device checks.

## Store and operational materials — pending

- [ ] Final app icon (the current asset is a placeholder).
- [ ] Final Czech/English store screenshots showing the selected design and real behavior.
- [ ] Store description, subtitle, keywords, category, age rating, review notes and contact information.
- [ ] Publish and verify durable support and privacy URLs. The in-app policy link currently targets the repository's main branch; confirm the updated policy is reachable there before public submission.
- [ ] Review App Store privacy declarations and both privacy manifests against the final binary, optional network checks and published policy.
- [ ] Check app/extension capabilities, permission wording, signing, export compliance and the final Release archive; confirm it contains no comparison controls or corpus.
- [ ] Run the public Release candidate on a physical device and complete App Store Connect validation/review submission.

Apple's [App Review guidance](https://developer.apple.com/app-store/review/) is the submission reference. Public submission is a separate delivery after these decisions and checks.

## Deferred scope

OCR comparison, reporting/backend, paste/share text, widgets/controls, Android and the marketing landing page remain deferred. Support and privacy pages are release materials; a marketing site is not required for the internal comparison build.
