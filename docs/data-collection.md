# Data collection (planned for M7)

The app works fully without any backend. The reporting service described here is **not implemented**. Proposed data sharing is opt-in and off by default. [PRIVACY.md](../PRIVACY.md) describes current behavior, not these future capabilities.

## Internal diagnostic export (0.0.10, implemented)

Settings → History can preview and share a JSON file containing saved ordinary payloads and
available check diagnostics, app/OS version and bounded payload-free camera events. Detected
secrets and protected access links are redacted at export. The user reviews the actual file and
chooses a recipient in the native share sheet. There is no automatic uploader, backend, device
identifier or consent switch. This internal support workflow does not implement the M7 service
below. Temporary files are removed after sharing/cancellation; old history is never rechecked
silently to reconstruct diagnostics.

## Onboarding comparison (0.0.8, internal preview)

The 0.0.8 Design Lab contained a native introduction and choice screen; its entry point is retired in 0.0.10. The prototype remains in source. It is not part of live onboarding,
does not save consent and has no uploader. Trial choices are view-local and reset on dismissal.
The app prominently identifies the preview and explains that nothing is sent.

The smaller first-version proposal shown there is:

- Independently optional suspicious-link reports, reviewed and confirmed individually before sending.
- Independently optional aggregate counts of check outcomes and error categories, with app version;
  no QR contents, addresses, photos, location or persistent device identifier in diagnostics.
- No photos, location, payment reporting or automatic reports in that first step. These remain
  separate future decisions. Both choices start off; continuing without sharing is always available.

Before replacing the preview with real consent, define the exact payload and filtering rules,
retention/deletion, server logging (including IP handling), operator/contact information and
withdrawal behavior. Implement and test that contract, update the published policy and App Store
declarations, and obtain a fresh choice from users. A preview choice must never enable uploads later.

There is no general iOS analytics-sharing permission dialog. For the proposed first-party service,
use the app's own informed choice. Apple's ATT prompt applies to the tracking defined in its
[data-use guidance](https://developer.apple.com/app-store/user-privacy-and-data-use/). A future
location attachment would request system permission only when the person chooses that feature,
following Apple's [location authorization guidance](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services).

The broader M7 proposal below remains a draft and is not enabled by the onboarding comparison.

## Two independent consents (15+ only)

1. **Share details of suspicious codes.** Sent only for eligible Caution/Dangerous scans:
   - the sanitised link and its observed redirect chain (tokens and personal identifiers stripped);
   - signal IDs;
   - for dangerous payments, the bank code, the amount, and the account number as a server-side keyed hash (never the payee name);
   - approximate location (≈ 1 km);
   - content-free daily counters.
2. **Automatic report of dangerous codes with photo and precise location.** Applies to dangerous *camera* scans only.
   - The photo is cropped around the sticker, with faces, people, number plates, other codes and non-essential text masked.
   - The code's own modules are masked too, because the pixels would otherwise leak what we removed from the link.
   - Metadata is stripped, and ambiguous images are dropped.
   - The report is sent after a visible, adjustable cancel window, or only on manual confirmation.

## Never collected
- Sensitive codes: 2FA secrets, login/device-link tokens, seed phrases, Wi‑Fi passwords, boarding passes, health certificates.
- Contacts and calendar entries.
- Device identifiers used for tracking.
- Images from the gallery or the share extension.

## Safeguards
- **Purposes:** detecting and correlating scam campaigns, improving detection, and locating scam stickers.
- **Retention:** photos and GPS 30 days, reports 90 days; documented case holds only.
- **Deletion receipts** let people view, export or delete their reports without an account. Withdrawing consent deletes the server-side data too.
- **Access and publication:**
  - private storage with MFA and least-privilege access;
  - no public feeds or maps with photos, locations or payee data;
  - police referrals are manual, logged and disclosed.
- **Documentation:** we complete our own DPIA, LIA and RoPA before real uploads are switched on.
