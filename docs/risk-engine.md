# Risk engine

The engine answers three separate questions about every scanned code:

1. **Fraud evidence**: the *orientační skóre rizika* (indicative risk index) from 0 to 100.
2. **Consequence**: what the code would do, for example start a recurring payment, forward your calls or link a device. This is never counted as fraud.
3. **Inspection completeness**: complete / incomplete / skipped / not needed, and why.

Destination resolution is recorded separately: scanned address, last observed HTTP response, resolved endpoint or unresolved/app-handoff state. A blocked or unvisited redirect target is not a confirmed final page.

An unavailable check never overrides danger that has already been established.

The reference implementation is [`scripts/lib/engine.mjs`](../scripts/lib/engine.mjs). The Swift (BQCore) and Kotlin ports must reproduce its numbers for every sample in [`shared/testdata/samples.json`](../shared/testdata/samples.json).

## Pipeline

```
payload (string + raw bytes) → classifier → sensitivity gate → parser → evidence providers → per-type engine → assessment
```

- **The sensitivity gate runs first and cannot be overridden.** It covers 2FA secrets/exports, login and device-link tokens, FIDO, WalletConnect, seed phrases, Wi‑Fi passwords and personal documents. For these codes:
  - nothing is fetched;
  - the payload is never stored in history (a redacted summary only);
  - nothing goes into telemetry or reports;
  - camera frames are discarded.
- **Implemented evidence providers:** lexical URL analysis, bundled lists, payment and SMS/phone rules, destination inspection, Quad9 protective DNS and RDAP domain age. Printed-text OCR comparison and remote intelligence remain deferred; OCR findings can be exercised with synthetic fixtures.

## Score

```
score = round(100 · sigmoid(baseline + Σ_groups min(cap, combine(weights))))
```

- **Evidence groups** keep correlated signals from inflating the score. For example TLD, free hosting, randomness and domain age are all "weak provenance" and share one cap.
- **Weak-only cap:** evidence made up only of weak provenance, transport or OCR can never exceed **59** (Caution).
- **Floors** apply afterwards, only for strong, specific evidence:
  - 25 for a credible identity or context discrepancy;
  - 80 for secret exfiltration, a deceptive subscription or a provider security block;
  - 95 for a reviewed malicious match.
- **Allowlists only switch off impersonation and redirect heuristics.** They never add trust and never cancel malicious-content evidence.
- **Weights** are in [`shared/rules/weights.json`](../shared/rules/weights.json). They are an uncalibrated starter set that will be calibrated on independently labelled data later.

| Band | Range | Wording |
|---|---|---|
| Bez známých hrozeb | 0–24 | "V provedených kontrolách jsme nenašli varovné znaky." Never "safe" or "verified" |
| Buďte opatrní | 25–59 | Leads with the specific concern |
| Nebezpečné | 60–100 | Likely consequence + what to do |
| Nelze ověřit | inspection incomplete and score < 25 | What remains unchecked; muted score |

## Link inspection

**Before any network contact:**
1. Local lists and domain-only checks run first.
2. Links that look like login, confirmation, redemption or unsubscribe URLs, or that contain tokens, are **not** fetched automatically.
3. Private and special-use addresses are refused.

**The gate in detail** (`LinkGate`, hardened after two rounds of independent security review):
- One canonical host for every check and for the request itself: lower-case punycode, one trailing dot removed. Hosts with empty labels, percent-escapes or brackets around anything but an IPv6 address are refused as ambiguous, and so are paths with `.`/`..` segments or escapes left after decoding.
- Mobile-operator sites and carrier-billing hosts are never contacted, on any hop, including as the scanned link. Login and device-link URLs (Steam, Discord) are never contacted either.
- Tokens: known token parameters, JWTs, UUIDs, long hex and any other opaque parameter value of 24+ characters (marketing labels such as `utm_*` and click IDs excepted). Path segments get a readable-slug exemption for article URLs. Parameter values are decoded up to four more layers and nested URLs or query strings are checked too; a URL nested two levels deep, credentials inside a nested URL, or encoding that can't be resolved (including invalid UTF-8) counts as a token or refuses the link.
- Store hand-offs (`itms-apps`, `market`…) end a clean walk as complete; after any earlier degradation the inspection stays incomplete.

**How pages are fetched:**
- HTTPS only. For `http://` links the HTTPS variant is tried and cleartext is never fetched.
- One streamed GET per hop, with no cookies and no JavaScript.
- Every redirect hop is re-checked against all the rules above.
- Budgets: 10 requests, eight seconds overall (domain checks included), three seconds per hop, 2 MiB decoded per page and 4 MiB decoded across the walk.
- The walk **stops before any mobile-operator or carrier-billing host**, so your phone number isn't exposed.
- The result is the **observed** redirect chain plus what the page asks for: prices and intervals, phone, OTP, card and password fields, claimed brands.
- Redirects without a target, unsupported refreshes, detected script navigation, HTTP failures, loops, exhausted budgets and unresolved known shorteners produce incomplete outcomes. No JavaScript executes and no cookies are shared; browser-dependent destinations may remain unresolved. Page evidence already found is retained.
- An ordinary web URL that resolves completely opens the inspected HTTPS endpoint directly. Sensitive, special-purpose, incomplete, app-handoff and fragment-dependent routes retain their existing action policy and original-route explanation. Existing risk confirmations still apply.
- History stores the resolved hostname as its title after a successful check but keeps the scanned payload for an explicit recheck. Old history is never silently checked again.

**The subscription-page detector** needs all three of these before it raises the score to 80 or more:
- a recurring price (e.g. "99 Kč týdně");
- an activation mechanism;
- independent deception (e.g. "zdarma" or a parking/menu promise replaced by a subscription).

A clearly disclosed free trial never qualifies. See [`shared/rules/dcb.json`](../shared/rules/dcb.json).

## Czech specifics
- **Premium SMS** (APMS code 5.6):
  - 7 digits `90z xy ab`: AB Kč per sent SMS;
  - 8 digits `90z xy abc`: ABC Kč per received SMS;
  - 5 digits: an ordering number whose price isn't encoded;
  - the category comes from `z`, e.g. 902 = tickets/parking.
- **Premium voice numbers:**
  - 900, 906, 909: per-minute price;
  - 905: 10×AB per call;
  - 908: AB per call.
- **QR Platba:** IBAN mod-97, Czech mod-11 account check, ČNB bank codes, optional CRC32.
  - A code that names a state institution but whose account is not at ČNB (0710) gets a Caution explainer.
  - The recipient name inside a code is never verified. Czech banks will only verify payee names for euro payments, from July 2027.
- **Parking:** official hosts and their expected redirect relationships per city ([`parking.json`](../shared/rules/parking.json)).

## Implementation notes (BQCore)

The Swift engine lives in [`ios/Packages/BQCore`](../ios/Packages/BQCore) (`Parsers/`, `Risk/Detector.swift`, `Risk/Scorer.swift`, `Risk/LinkGate.swift`). `swift test` replays the whole corpus: type, parsed fields, evidence, consequences and band must match for all 80 samples. Decisions taken while implementing:

- **Brand look-alikes** match a brand token as a whole host label or hyphen-separated part. Substring matches need a token of **7+** characters (brands.json allows 6), so legitimate sites such as seznamka.cz don't look like Seznam.cz.
- **Every observed hop** (the scanned host, redirect targets and the final page) gets the same lexical rules; a signal ID counts once however many hops repeat it.
- **`url.transport.http`** is dropped when the HTTPS variant of an `http://` link was inspected successfully — that variant is what we checked and what opens.
- **`url.identity.false_official`**: the page presents itself as a brand (title, headings, logo text) on a domain the brand doesn't own. With a card field it also raises `page.solicit.card_false_identity`.
- **`page.solicit.credentials_unrelated`**: card, password or SMS-code fields on a page that talks about prizes or gifts, or an HTML form embedded in a `data:` URI.
- **Domain age** counts from the scan date: under 7 days or under 30 days is weak evidence; older domains only produce a "registered since" check and never add trust.
