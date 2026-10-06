import BQCore

/// A clearer explanation of the existing incomplete outcome; never changes its score or policy.
enum InspectionExplanation {
    static func text(_ analysis: Analysis, _ language: Language) -> String {
        let key: String?
        switch analysis.inspection?.transportError {
        case "nameNotResolved", "resolverFailed": key = "dns"
        case "connectionFailed", "offline": key = "connection"
        case "tlsFailed", "unsupportedProtocol", "bindingUnproven", "unverifiableAddress": key = "secure"
        case "malformedResponse", "decodingFailed": key = "format"
        default:
            if analysis.completeness.reason == "inc.http_error", let status = analysis.inspection?.chain.last(where: { $0.status != nil })?.status {
                if [401, 403, 429].contains(status) { key = "access" }
                else if [404, 410].contains(status) { key = "missing" }
                else if status >= 500 { key = "server" }
                else { key = nil }
            } else { key = nil }
        }
        if let key { return language.t("check.reason." + key) }
        return RuleSet.bundled.texts.incomplete(analysis.completeness.reason, language)
    }
}
