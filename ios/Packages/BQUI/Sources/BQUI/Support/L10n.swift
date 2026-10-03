import BQCore
import Foundation
import SwiftUI

/// UI strings of Bezpečné QR (cs + en), generated from the prototype by scripts/gen-ui-strings.mjs.
///
/// Placeholders use `{name}`, exactly like the prototype: `L10n.t("check.redirects", ["n": "2"], .cs)`.
/// A missing key falls back to Czech, then to the key itself (and is recorded in DEBUG builds so
/// tests can fail on it).
public enum L10n {
    /// `[language: [key: text]]`, loaded once from the module bundle.
    static let table: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "ui-strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            assertionFailure("BQUI: ui-strings.json is missing — run scripts/gen-ui-strings.mjs")
            return [:]
        }
        var out: [String: [String: String]] = [:]
        for language in Language.allCases {
            out[language.rawValue] = object[language.rawValue] as? [String: String] ?? [:]
        }
        return out
    }()

    /// The localized string for `key`, with `{placeholders}` filled from `args`.
    public static func t(_ key: String, _ args: [String: String] = [:], _ lang: Language) -> String {
        let template = table[lang.rawValue]?[key] ?? table[Language.cs.rawValue]?[key] ?? missing(key)
        return args.isEmpty ? template : fill(template, args)
    }

    /// The localized string for `key` (no placeholders).
    public static func t(_ key: String, _ lang: Language) -> String {
        t(key, [:], lang)
    }

    /// Whether a string exists for `key`.
    public static func has(_ key: String) -> Bool {
        table[Language.cs.rawValue]?[key] != nil
    }

    /// Replaces `{name}` with `args["name"]`; unknown placeholders are kept as they are.
    static func fill(_ template: String, _ args: [String: String]) -> String {
        var out = ""
        var index = template.startIndex
        while index < template.endIndex {
            let c = template[index]
            if c == "{", let close = template[index...].firstIndex(of: "}") {
                let name = String(template[template.index(after: index)..<close])
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), let value = args[name] {
                    out += value
                    index = template.index(after: close)
                    continue
                }
            }
            out.append(c)
            index = template.index(after: index)
        }
        return out
    }

    #if DEBUG
    /// Keys that were requested but don't exist (checked by the tests).
    static var missingKeys: Set<String> {
        get { missingLock.withLock { _missingKeys } }
        set { missingLock.withLock { _missingKeys = newValue } }
    }
    nonisolated(unsafe) private static var _missingKeys = Set<String>()
    private static let missingLock = NSLock()
    #endif

    private static func missing(_ key: String) -> String {
        #if DEBUG
        missingLock.withLock { _ = _missingKeys.insert(key) }
        #endif
        return key
    }
}

extension Language {
    /// Shorthand used inside BQUI views: `lang.t("band.safe")`.
    func t(_ key: String, _ args: [String: String] = [:]) -> String {
        L10n.t(key, args, self)
    }

    var locale: Locale {
        Locale(identifier: self == .cs ? "cs_CZ" : "en_GB")
    }
}

extension EnvironmentValues {
    /// The language BQUI views render in. `ResultScreen` sets it from `ResultModel.language`;
    /// other screens of the app can set it once at the root: `.environment(\.bqLanguage, .cs)`.
    @Entry public var bqLanguage: Language = .preferred

    /// Renders without scroll views, delayed states and appear animations (snapshot tests).
    @Entry var bqSnapshot: Bool = false
}
