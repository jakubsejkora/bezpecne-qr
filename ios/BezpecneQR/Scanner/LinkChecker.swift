import BQCore
import BQServices
import BQUI
import Foundation

/// Adapter between the scan flow and BQServices' link inspector. One inspector lives for the
/// whole app session so the Quad9 and RDAP caches carry over between scans.
struct LinkChecker: LinkChecking {
    let inspector = LinkInspector()

    func check(_ url: URL, pageFetch: Bool, domainChecks: Bool, manual: Bool,
               progress: @escaping @Sendable (CheckStep) -> Void) async -> Inspection {
        var options = InspectionOptions()
        options.pageFetch = pageFetch
        options.domainChecks = domainChecks
        return await inspector.inspect(url, options: options, manualOverride: manual) { step in
            switch step {
            case .checkingAddress: progress(.address)
            case .checkingDomain: progress(.domain)
            case .followingRedirects(let count): progress(.redirects(count))
            case .readingPage: progress(.page)
            }
        }
    }
}
