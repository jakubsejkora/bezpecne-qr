# Data collection (planned for M7)

The app works fully without any backend. Data sharing is **opt-in** and off by default. The full user-facing text is in [PRIVACY.md](../PRIVACY.md).

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
