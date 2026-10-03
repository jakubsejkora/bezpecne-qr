import Foundation

/// How the score was computed (shown in the developer diagnostics).
public struct ScoreMath: Sendable, Hashable {
    public struct Group: Sendable, Hashable {
        public var group: String
        public var signals: [String]
        public var combined: Double
        public var cap: Double
        public var contribution: Double
    }

    public var baseline: Double
    public var groups: [Group]
    public var logit: Double
    public var raw: Double
    public var weakOnlyCapApplied: Double?
    public var floorApplied: (id: String, floor: Int)?

    public static func == (a: ScoreMath, b: ScoreMath) -> Bool {
        a.baseline == b.baseline && a.groups == b.groups && a.logit == b.logit && a.raw == b.raw
            && a.weakOnlyCapApplied == b.weakOnlyCapApplied && a.floorApplied?.id == b.floorApplied?.id
            && a.floorApplied?.floor == b.floorApplied?.floor
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(baseline)
        hasher.combine(groups)
        hasher.combine(logit)
        hasher.combine(raw)
    }
}

/// The verdict: an indicative 0–100 risk score and its band.
public struct Assessment: Sendable, Hashable {
    /// False for informational, unscored types (band `info`, no meter).
    public var scored: Bool
    public var score: Int?
    public var band: Band
    public var math: ScoreMath?

    public init(scored: Bool, score: Int?, band: Band, math: ScoreMath? = nil) {
        self.scored = scored
        self.score = score
        self.band = band
        self.math = math
    }
}

/// Everything the app knows about one scanned code.
public struct Analysis: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var code: ScannedCode
    public var type: CodeType
    public var subtype: LinkSubtype?
    public var content: CodeContent
    public var engine: EngineKind
    public var sensitivity: Sensitivity?
    /// Scored evidence, strongest first.
    public var evidence: [Finding]
    /// What the code would do, most severe first. Never part of the score.
    public var consequences: [Finding]
    /// What we verified.
    public var checks: [Finding]
    public var completeness: Completeness
    public var inspection: Inspection?
    public var assessment: Assessment
    /// The code is broken or inconsistent; the hand-off (payment, call…) must be blocked.
    public var invalid: Bool
    /// Decode-only types never show a risk meter.
    public var decodeOnly: Bool
    /// The link to inspect over the network, if any (nil when inspection is not applicable).
    public var linkTarget: URL?
    /// The link that "Otevřít" opens (may be the HTTPS-upgraded variant).
    public var openURL: URL?

    public init(id: UUID = UUID(), code: ScannedCode, type: CodeType, subtype: LinkSubtype? = nil,
                content: CodeContent, engine: EngineKind, sensitivity: Sensitivity? = nil,
                evidence: [Finding] = [], consequences: [Finding] = [], checks: [Finding] = [],
                completeness: Completeness = .complete, inspection: Inspection? = nil,
                assessment: Assessment, invalid: Bool = false, decodeOnly: Bool = false,
                linkTarget: URL? = nil, openURL: URL? = nil) {
        self.id = id
        self.code = code
        self.type = type
        self.subtype = subtype
        self.content = content
        self.engine = engine
        self.sensitivity = sensitivity
        self.evidence = evidence
        self.consequences = consequences
        self.checks = checks
        self.completeness = completeness
        self.inspection = inspection
        self.assessment = assessment
        self.invalid = invalid
        self.decodeOnly = decodeOnly
        self.linkTarget = linkTarget
        self.openURL = openURL
    }

    public var band: Band { assessment.band }
    public var isSensitive: Bool { sensitivity != nil }
}

/// User settings that change how a code is analysed.
public struct AnalysisOptions: Sendable, Hashable {
    /// "Kontrola odkazu (načtení stránky)".
    public var pageFetch: Bool
    /// "Veřejné kontroly domény" (Quad9 + RDAP).
    public var domainChecks: Bool
    /// The device is offline.
    public var offline: Bool

    public init(pageFetch: Bool = true, domainChecks: Bool = true, offline: Bool = false) {
        self.pageFetch = pageFetch
        self.domainChecks = domainChecks
        self.offline = offline
    }
}
