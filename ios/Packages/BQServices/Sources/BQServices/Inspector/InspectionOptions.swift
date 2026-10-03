import BQCore
import Foundation

/// Settings and budgets for one inspection.
public struct InspectionOptions: Sendable, Hashable {
    /// "Kontrola odkazu (načtení stránky)": load the link. Off means no request to the link at all.
    public var pageFetch: Bool
    /// "Veřejné kontroly domény": Quad9 and RDAP. Off means no request to either service.
    public var domainChecks: Bool
    /// Requests to the link and its redirects (domain checks not included).
    public var maxRequests: Int
    /// Everything, domain checks included, finishes by then.
    public var overallDeadline: Duration
    /// One request: DNS, connect, TLS and the response.
    public var hopDeadline: Duration
    /// Decompressed bytes kept per page and in total.
    public var maxPageBytes: Int
    public var maxTotalBytes: Int

    public init(pageFetch: Bool = true, domainChecks: Bool = true, maxRequests: Int = 10,
                overallDeadline: Duration = .seconds(8), hopDeadline: Duration = .seconds(3),
                maxPageBytes: Int = 2 * 1024 * 1024, maxTotalBytes: Int = 4 * 1024 * 1024) {
        self.pageFetch = pageFetch
        self.domainChecks = domainChecks
        self.maxRequests = maxRequests
        self.overallDeadline = overallDeadline
        self.hopDeadline = hopDeadline
        self.maxPageBytes = maxPageBytes
        self.maxTotalBytes = maxTotalBytes
    }
}

/// Steps the "Kontroluji…" sheet can show, in the order they happen.
public enum InspectionProgress: Sendable, Hashable {
    /// Checking the scanned address ("Rozbaluji zkrácený odkaz…" when it is a short link).
    case checkingAddress(shortLink: Bool)
    /// Quad9 and the domain registry.
    case checkingDomain
    /// Redirects followed so far.
    case followingRedirects(count: Int)
    /// Reading what the landing page asks for.
    case readingPage
}

/// `Completeness.reason` IDs produced by the inspector (texts in shared/rules/signals.json).
public enum IncompleteReason {
    public static let offline = "inc.offline"
    public static let timeout = "inc.timeout"
    public static let billingStop = "inc.billing_stop"
    public static let httpsFailed = "inc.https_failed"
    public static let checksDisabled = "inc.checks_disabled"
    public static let jsOnly = "inc.js_only"
    public static let domainBlocked = "inc.domain_blocked"
    public static let notLoadedFile = "inc.not_loaded_file"
    public static let notLoadedProfile = "inc.not_loaded_profile"
    public static let notLoadedCalendar = "inc.not_loaded_calendar"
    public static let refusedLocal = "inc.refused_local"
    public static let refusedScheme = "inc.refused_scheme"
    public static let refusedAmbiguous = "inc.refused_ambiguous"
    // Not yet in shared/rules/signals.json (texts proposed in the BQServices README):
    /// The site could not be loaded: DNS, connection, TLS, protocol or binding failure.
    public static let fetchFailed = "inc.fetch_failed"
    /// Too many redirects (request or byte budget) or a redirect loop.
    public static let redirectLimit = "inc.redirect_limit"
    /// The page is larger than the budget or arrived incomplete; only its beginning was read.
    public static let pageTruncated = "inc.page_truncated"

    /// Why the gate refused a URL (same IDs as BQCore's analyzer).
    public static func refused(_ refusal: LinkGate.Refusal) -> String {
        switch refusal {
        case .privateAddress, .localName: return refusedLocal
        case .unsupportedScheme: return refusedScheme
        case .ambiguous, .invalid: return refusedAmbiguous
        }
    }

    /// Why a file was not loaded, by the same extensions as `LinkGate`'s file rule.
    public static func notLoaded(_ url: URL) -> String {
        let path = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.path).lowercased()
        if path.hasSuffix(".mobileconfig") { return notLoadedProfile }
        if [".ics", ".ical", ".vcs"].contains(where: path.hasSuffix) { return notLoadedCalendar }
        return notLoadedFile
    }
}
