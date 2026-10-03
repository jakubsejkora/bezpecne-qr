import Foundation

/// What the link inspector observed for a link. Produced by BQServices (`LinkInspector`) and
/// consumed by the risk engine. The shape matches `inspection` in shared/testdata/samples.json,
/// so corpus samples can be replayed without network access.
public struct Inspection: Sendable, Hashable, Codable {
    /// Every request we made or deliberately did not make, in order.
    public var chain: [Hop]
    /// The last page we actually loaded, if any.
    public var final: Endpoint?
    /// What that page contains and asks for.
    public var page: PageFacts?
    /// Public domain checks (protective DNS and registration date).
    public var domain: DomainFacts?
    /// Whether the inspection finished. Nil in corpus mocks (the sample's own completeness applies).
    public var completeness: Completeness?

    public init(chain: [Hop] = [], final: Endpoint? = nil, page: PageFacts? = nil, domain: DomainFacts? = nil,
                completeness: Completeness? = nil) {
        self.chain = chain
        self.final = final
        self.page = page
        self.domain = domain
        self.completeness = completeness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chain = try c.decodeIfPresent([Hop].self, forKey: .chain) ?? []
        final = try c.decodeIfPresent(Endpoint.self, forKey: .final)
        page = try c.decodeIfPresent(PageFacts.self, forKey: .page)
        domain = try c.decodeIfPresent(DomainFacts.self, forKey: .domain)
        completeness = try c.decodeIfPresent(Completeness.self, forKey: .completeness)
    }
}

/// One step of a redirect chain.
public struct Hop: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        case shortener
        case openRedirect = "open-redirect"
        case httpsUpgrade = "https-upgrade"
        case curatedRelationship = "curated-relationship"
        case metaRefresh = "meta-refresh"
    }

    /// Why we did not load (or finish loading) this hop.
    public enum Stop: String, Sendable, Codable {
        /// Operator or carrier-billing host — never contacted, to protect the phone number.
        case billing
        /// The scanned link itself is a mobile operator's website (not a billing host) — not contacted either.
        case operatorSite = "operator-site"
        case timeout
        /// The eligibility gate refused it (token, private address, unsupported scheme…).
        case gate
        case tlsFailed = "tls-failed"
        case error
        /// The redirect budget (hops, time or bytes) was exhausted.
        case budget
        case loop
    }

    public var url: String
    /// HTTP status, nil when no response was received.
    public var status: Int?
    public var kind: Kind?
    public var stopped: Stop?

    public init(url: String, status: Int? = nil, kind: Kind? = nil, stopped: Stop? = nil) {
        self.url = url
        self.status = status
        self.kind = kind
        self.stopped = stopped
    }
}

public struct Endpoint: Sendable, Hashable, Codable {
    public var url: String
    public var host: String
    public var registrable: String

    public init(url: String, host: String, registrable: String) {
        self.url = url
        self.host = host
        self.registrable = registrable
    }
}

/// What a page asks the visitor to enter.
public enum AskKind: String, Sendable, Codable, CaseIterable {
    case card
    case phone
    case password
    /// One-time / SMS code.
    case otp
    case email
    case licencePlate
    /// Recovery phrase, backup codes or private keys.
    case recoverySecret
    case personalID
}

/// A recurring charge found on a page ("Předplatné 99 Kč/týden").
public struct Offer: Sendable, Hashable, Codable {
    /// The charge, quoted verbatim from the page.
    public var text: String
    /// A "free" / prize promise on the same page that the charge contradicts, quoted verbatim.
    public var promise: String?
    /// Indexes into `PageFacts.extract` of lines to highlight.
    public var highlight: [Int]

    public init(text: String, promise: String? = nil, highlight: [Int] = []) {
        self.text = text
        self.promise = promise
        self.highlight = highlight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        promise = try c.decodeIfPresent(String.self, forKey: .promise)
        highlight = try c.decodeIfPresent([Int].self, forKey: .highlight) ?? []
    }
}

/// A bounded, inert summary of a page ("Výtah ze stránky"). Never contains active content.
public struct PageFacts: Sendable, Hashable, Codable {
    /// `<title>` (or the first heading) — the page's own claim, not verified.
    public var title: String?
    /// Visible text lines in reading order. Form fields appear as `Label: [          ]` and
    /// buttons as `[ Label ]`.
    public var extract: [String]
    public var asks: [AskKind]
    public var offer: Offer?
    /// A brand from brands.json that the page presents itself as (title, headings, logo text).
    public var brandClaim: String?
    /// The page contains an app install / configuration-profile link.
    public var installLink: String?
    /// Names of remote-access tools mentioned or linked (AnyDesk, TeamViewer…).
    public var remoteAccess: [String]
    /// `<form action>` hosts that differ from the page host.
    public var foreignFormHosts: [String]

    public init(title: String? = nil, extract: [String] = [], asks: [AskKind] = [], offer: Offer? = nil,
                brandClaim: String? = nil, installLink: String? = nil, remoteAccess: [String] = [],
                foreignFormHosts: [String] = []) {
        self.title = title
        self.extract = extract
        self.asks = asks
        self.offer = offer
        self.brandClaim = brandClaim
        self.installLink = installLink
        self.remoteAccess = remoteAccess
        self.foreignFormHosts = foreignFormHosts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        extract = try c.decodeIfPresent([String].self, forKey: .extract) ?? []
        asks = try c.decodeIfPresent([AskKind].self, forKey: .asks) ?? []
        offer = try c.decodeIfPresent(Offer.self, forKey: .offer)
        brandClaim = try c.decodeIfPresent(String.self, forKey: .brandClaim)
        installLink = try c.decodeIfPresent(String.self, forKey: .installLink)
        remoteAccess = try c.decodeIfPresent([String].self, forKey: .remoteAccess) ?? []
        foreignFormHosts = try c.decodeIfPresent([String].self, forKey: .foreignFormHosts) ?? []
    }
}

/// Results of the public domain checks.
public struct DomainFacts: Sendable, Hashable, Codable {
    public enum Quad9: String, Sendable, Codable {
        case ok, blocked, unknown
    }

    /// The domain that was checked (registrable domain).
    public var name: String?
    /// Registration date as ISO `yyyy-MM-dd`, or free text when only approximate.
    public var registered: String?
    /// Registry / RDAP server label, e.g. "CZ.NIC".
    public var registry: String?
    public var quad9: Quad9?

    public init(name: String? = nil, registered: String? = nil, registry: String? = nil, quad9: Quad9? = nil) {
        self.name = name
        self.registered = registered
        self.registry = registry
        self.quad9 = quad9
    }
}

/// Printed text recognised next to the selected code (OCR), used for printed-vs-QR checks.
public struct PrintedContext: Sendable, Hashable, Codable {
    /// A domain printed next to the code, e.g. "parking.praha.eu".
    public var printed: String?
    /// Other text near the code.
    public var near: String?

    public init(printed: String? = nil, near: String? = nil) {
        self.printed = printed
        self.near = near
    }
}
