# BQServices

The network side of Bezpečné QR: before a scanned link opens, the app loads it itself — without
cookies, JavaScript or the user's identity — and reports the observed redirect chain, what the
landing page asks for and the public domain checks. Output is BQCore's `Inspection`.
Extension-safe, no third-party dependencies, iOS 18 / macOS 15, Swift 6 strict concurrency.

## Components

| Type | What it does |
|---|---|
| `LinkInspector` (actor) | `inspect(_:options:manualOverride:progress:) async -> Inspection`. Walks redirects (`Location`, meta refresh ≤ 10 s, known open redirectors), runs `LinkGate` before every hop, analyses the final page, runs Quad9 + RDAP concurrently. Never throws. |
| `SafeFetcher` | One HTTP/1.1 GET over Network.framework per call (`HTTPTransport`). Vets, binds, verifies TLS, parses and decodes within budgets. |
| `AddressVetter` (`HostVetting`) | System resolver + address rules, including NAT64 prefix discovery (RFC 7050, cached per network path). Used before every connection and before a name may go to the public checks. |
| `HTTPResponseParser`, `BodyDecoder`, `Inflate` | Pure RFC 9112 parser; content decoding. gzip and deflate use our own bit-exact RFC 1951 decoder (after puff.c), Brotli the Compression framework. No libz. |
| `PageAnalyzer` | Bounded, streaming HTML tokenizer of our own → `PageFacts`: title, extract (`Label: [          ]`, `[ Button ]`), asks, offer + promise (dcb.json patterns), brand claim, install link, remote-access tools, foreign form hosts; plus meta-refresh and JS-redirect candidates. No WebKit, no `NSAttributedString` HTML import, nothing executed or fetched. Reports when a limit stopped it (`truncated`). |
| `Quad9Client` | One RFC 8484 DoH POST (type A, EDNS padding, no ECS). Block = NXDOMAIN with an empty authority section (or EDE Blocked/Filtered); NXDOMAIN with an SOA is a non-existent name, not a block. Cached by TTL, backs off after 429/5xx. |
| `RDAPClient` | Registration date (`yyyy-MM-dd`, Europe/Prague) via the bundled IANA bootstrap. HTTPS only, no redirects, 1 request/s per registry, coalesced (each caller keeps its own deadline), cached 1 h, backs off on 429/503. Missing data is unknown, never "old". |
| `URLSessionEndpointClient` | URLSession (ephemeral) for Quad9 and RDAP: our own server-trust evaluation (as in SafeFetcher), never follows redirects, never answers auth challenges, streams the body and cancels past 256 KiB. |

`Quad9Client.shared` and `RDAPClient.shared` (the `DomainChecker` defaults) are process-wide, so
caches, back-off and request spacing hold however many inspectors exist.

`Resources/rdap-dns.json` is the IANA RDAP bootstrap (https://data.iana.org/rdap/dns.json), retrieved
2026-10-03 (publication 2026-09-30T23:00:03Z). Refresh it with
`curl -sS https://data.iana.org/rdap/dns.json -o Sources/BQServices/Resources/rdap-dns.json` before releases.

## Security properties

- **Gate on every hop.** `LinkGate.evaluate(url, hop:)` runs before each request (scanned link = hop 0).
  `http://` is upgraded to HTTPS on the same host; cleartext is never loaded. Tokens and sign-in paths
  are skipped, private/local/odd targets refused, operator and carrier-billing hosts never contacted
  (`stopped: billing`). Ambiguous `Location` values (backslash, whitespace, controls) are refused.
- **Address vetting.** Every A/AAAA answer of the system resolver must be public; one non-public
  answer refuses the name (DNS rebinding / SSRF). NAT64: the network's translation prefixes are
  discovered from the AAAA records synthesized for `ipv4only.arpa` (RFC 7050, all RFC 6052
  layouts /32–/96) and cached per network path; an IPv6 answer inside such a prefix must embed a
  public IPv4 address. IPv6 answers are used only when a prefix was discovered: without one (no
  DNS64, or discovery failed) a translator with an unknown prefix may exist even on dual-stack
  networks, so only IPv4 answers are used — the system translates them where needed — and an
  IPv6-only answer fails (`unverifiableAddress`). On most networks that means IPv4 only.
- **Hosts.** Brackets are accepted only around an IPv6 literal (`https://[o2platba.cz]/` is refused
  before DNS, SNI or `Host`). Resolver errors other than "no such name" are `resolverFailed`.
- **Binding.** Connections go to the vetted IP endpoints (≤ 2 raced, 250 ms stagger), never the
  hostname. After `ready`, the peer must be the vetted address (or the system's NAT64 form of a
  vetted IPv4) and the establishment report must show no proxy; otherwise the fetch fails
  (`bindingUnproven`). Only then is the single GET sent.
- **TLS.** ≥ 1.2, SNI = hostname (none for IP literals), trust = `SecPolicyCreateSSL(true, host)`
  against system anchors with network fetches disabled (no AIA/OCSP traffic; stapled OCSP and SCTs
  are used). No session resumption, tickets, false start, 0-RTT or TCP fast open. ALPN offers only
  `http/1.1`; anything else fails. The Quad9/RDAP client applies the same evaluation in its
  URLSession challenge handler and cancels on failure (the default evaluation would download a
  missing issuer from a URL the peer names — incomplete-chain.badssl.com shows the difference).
- **Request.** `GET` with Host, a mobile-Safari User-Agent, Accept, `Accept-Language: cs-CZ…`,
  `Accept-Encoding: gzip, deflate, br`, `Connection: close`. No cookies, Referer, credentials or
  fragment; auth challenges are never answered.
- **Parsing.** Strict status line and fields (obs-fold, bare CR, invalid names/values, conflicting
  Content-Length and TE + CL are rejected), 1xx skipped, chunked with extensions/trailers, CL and
  read-to-EOF framing, premature-close detection.
- **Content codings.** Decoded once the body ends, with trailers checked at the exact end of the
  coded data: every gzip member is decoded and its CRC32/ISIZE verified (back-references can't
  reach into an earlier member; at most 64 members); zlib's Adler-32 is verified; raw DEFLATE is
  assumed only without a valid zlib header. Bytes after the coded data, a missing trailer or a
  checksum mismatch fail the fetch (`decodingFailed`); a body cut short keeps what decodes.
- **Domain checks.** `pageFetch: false` sends nothing to the link; `domainChecks: false` sends
  nothing to Quad9 or RDAP. A name goes to them only after it resolved, through the system
  resolver, to vetted public addresses. A private answer (split DNS) ends the inspection
  `inc.refused_local` without loading anything; no such name, resolver failure, timeout or
  unverifiable answers keep the name on the device (the walk reports the fetch failure). IPs,
  local names and free-hosting tenants (RDAP) are never sent. No redirects are followed and
  responses are capped while streaming. A Quad9 block on the scanned domain means the page is not
  loaded at all.
- **No silent truncation.** A body cut at a byte cap, a deadline or a broken connection is
  accounted for before the response is classified or followed anywhere, so the inspection ends
  incomplete (`inc.page_truncated` / `inc.timeout`) — whether the response was a page, something
  unrecognizable, an open-redirect interstitial or a meta refresh. A page the analyzer could not
  read to the end counts the same.
- No logging.

## Budgets (defaults, `InspectionOptions`)

| Budget | Value |
|---|---|
| Requests to the link and its redirects | 10 |
| Overall deadline (domain checks included) | 8 s |
| Per request (DNS + TCP + TLS + body) | 3 s |
| Header section (all responses + trailers) | 32 KiB |
| Decoded page / all pages | 2 MiB / 4 MiB |
| Body as sent, per page | max(1 MiB, page budget) |
| Domain-check response | 256 KiB |
| Analyzer | 4 MiB of HTML, 1 M tokens, 10 000 lines, 500 fields, 200 forms (reported when reached) |
| Extract | 40 lines × 200 chars |

## Completeness reasons

`IncompleteReason` holds the IDs, all from `shared/rules/signals.json` (`inc.offline`, `inc.timeout`,
`inc.billing_stop`, `inc.operator_skipped` (an operator's own site scanned directly), `inc.https_failed`,
`inc.token_skipped`, `inc.auth_path_skipped`,
`inc.checks_disabled`, `inc.js_only`, `inc.domain_blocked`, `inc.not_loaded_*`, `inc.refused_*`)
except three that still need texts there (proposed):

| ID | cs | en |
|---|---|---|
| `inc.fetch_failed` | Web se nepodařilo načíst (chyba spojení nebo zabezpečení). | We couldn't load the website (connection or security error). |
| `inc.redirect_limit` | Přesměrování je příliš mnoho nebo se točí v kruhu — cíl neznáme. | Too many redirects or a redirect loop — the destination is unknown. |
| `inc.page_truncated` | Stránka je příliš velká, přečetli jsme jen její začátek. | The page is too large; we read only its beginning. |

`inc.js_only` is used only when a page is (nearly) empty and navigates by script; a page that merely
renders its content with script (e.g. vph.zpspraha.cz, an AngularJS app) is complete with an empty
extract.

## Tests

```sh
cd ios/Packages/BQServices
swift test                                   # unit tests, no network
BQ_LIVE_TESTS=1 swift test                   # plus live tests: example.com, parking.praha.eu, Quad9,
                                             # RDAP and the end-to-end suite (17 real sites)
```

Unit tests cover request serialization, parser fixtures at random fragmentation, the DEFLATE
decoder (stored/fixed/dynamic blocks, exact end, fuzzing), gzip members, zlib Adler-32, Brotli and
bombs, address vetting through the resolver path (no connection is ever created for a private or
NAT64-private answer), NAT64 prefix discovery and caching, the endpoint client over a mock
URLProtocol (no redirects, streaming cap), DNS encoding/decoding and the Quad9 block rule (real
captured answers), RDAP parsing and coalescing, the page analyzer on realistic pages and the
inspector with a fake transport and vetter.
