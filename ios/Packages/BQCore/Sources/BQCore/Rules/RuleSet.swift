import Foundation

/// The bundled rules from shared/rules and shared/content, decoded once.
public final class RuleSet: Sendable {
    public let weights: Weights
    public let texts: SignalTexts
    public let tlds: TLDRules
    public let brands: [Brand]
    public let parking: [ParkingCity]
    public let shorteners: Set<String>
    public let qrRedirectors: Set<String>
    public let freeHosts: [String]
    public let freeHostProviders: [String: String]
    public let dcb: DCBRules
    public let premium: PremiumRules
    public let wangiri: [WangiriPrefix]
    public let keywords: Keywords
    public let stateAccounts: StateAccountRules
    public let banks: [String: Bank]
    public let operatorGuide: OperatorGuide
    public let recoveryGuide: RecoveryGuide

    /// Rules bundled with the app.
    public static let bundled: RuleSet = {
        do {
            return try RuleSet(bundle: .module)
        } catch {
            fatalError("Bundled rules failed to load: \(error)")
        }
    }()

    public init(bundle: Bundle) throws {
        func load<T: Decodable>(_ folder: String, _ name: String, as type: T.Type = T.self) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: folder) else {
                throw RuleError.missing("\(folder)/\(name).json")
            }
            do {
                return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
            } catch {
                throw RuleError.invalid("\(folder)/\(name).json", error)
            }
        }
        weights = try load("rules", "weights")
        texts = try load("rules", "signals")
        tlds = try load("rules", "tlds")
        brands = try load("rules", "brands", as: BrandsFile.self).brands
        parking = try load("rules", "parking", as: ParkingFile.self).cities
        let shortenerFile = try load("rules", "shorteners", as: ShortenersFile.self)
        shorteners = Set(shortenerFile.shorteners)
        qrRedirectors = Set(shortenerFile.qrRedirectors)
        let free = try load("rules", "freehosts", as: FreeHostsFile.self)
        freeHosts = free.hosts
        freeHostProviders = free.providers ?? [:]
        dcb = try load("rules", "dcb")
        premium = try load("rules", "cz-premium")
        wangiri = try load("rules", "wangiri", as: WangiriFile.self).prefixes
        keywords = try load("rules", "keywords")
        stateAccounts = try load("rules", "state-accounts")
        banks = try load("rules", "bank-codes-cz", as: BanksFile.self).banks
        operatorGuide = try load("content", "operator-guide")
        recoveryGuide = try load("content", "recovery-guide")
    }

    public enum RuleError: Error, CustomStringConvertible {
        case missing(String)
        case invalid(String, Error)

        public var description: String {
            switch self {
            case .missing(let f): return "missing \(f)"
            case .invalid(let f, let e): return "invalid \(f): \(e)"
            }
        }
    }
}

// MARK: - weights.json

public struct Weights: Sendable, Decodable {
    public struct BandRange: Sendable, Decodable {
        public var id: Band
        public var min: Int
        public var max: Int
    }

    public struct WeakOnlyCap: Sendable, Decodable {
        public var groups: [String]
        public var cap: Double
    }

    public struct EngineConfig: Sendable, Decodable {
        public var baseline: Double
    }

    public struct Group: Sendable, Decodable {
        public enum Combine: String, Sendable, Decodable { case sum, max }
        public var cap: Double
        public var combine: Combine
    }

    public struct Signal: Sendable, Decodable {
        public var group: String
        public var weight: Double
        public var floor: Int?
    }

    public var engineVersion: String
    public var bands: [BandRange]
    public var weakOnlyCap: WeakOnlyCap
    public var engines: [String: EngineConfig]
    public var groups: [String: Group]
    public var signals: [String: Signal]
}

// MARK: - signals.json (texts)

public struct SignalTexts: Sendable, Decodable {
    public struct EvidenceText: Sendable, Decodable, Hashable {
        public var title: String
        public var observation: String
        public var implication: String
        public var action: String
    }

    public struct ConsequenceText: Sendable, Decodable, Hashable {
        public var title: String
        public var text: String
    }

    public struct ConsequenceEntry: Sendable, Decodable {
        public var severity: Severity
        public var cs: ConsequenceText
        public var en: ConsequenceText
    }

    public var evidence: [String: [String: EvidenceText]]
    public var consequences: [String: ConsequenceEntry]
    public var checks: [String: LocalizedText]
    public var incomplete: [String: LocalizedText]

    private enum CodingKeys: String, CodingKey { case evidence, consequences, checks, incomplete }
}

// MARK: - tlds.json

public struct TLDRules: Sendable, Decodable {
    public struct List: Sendable, Decodable {
        public var signal: String
        public var tlds: [String]
    }

    public var commonLegit: List
    public var abused: List
}

// MARK: - brands.json

public struct Brand: Sendable, Decodable, Hashable {
    public var id: String
    public var name: String
    public var tokens: [String]
    public var official: [String]
}

struct BrandsFile: Decodable { var brands: [Brand] }

// MARK: - parking.json

public struct ParkingCity: Sendable, Decodable {
    public var id: String
    public var name: String
    public var official: [String]
    public var relationships: [[String]]
    public var tip: LocalizedText?
    public var sms: String?
}

struct ParkingFile: Decodable { var cities: [ParkingCity] }

// MARK: - shorteners.json, freehosts.json

struct ShortenersFile: Decodable {
    var shorteners: [String]
    var qrRedirectors: [String]
}

struct FreeHostsFile: Decodable {
    var hosts: [String]
    var providers: [String: String]?
}

// MARK: - dcb.json

public struct DCBRules: Sendable, Decodable {
    public struct Aggregator: Sendable, Decodable {
        public var name: String
        public var domains: [String]
    }

    public struct Patterns: Sendable, Decodable {
        public var price: String
        public var interval: String
        public var subscription: String
        public var operatorBilling: String
        public var activation: String
        public var premiumNumber: String
    }

    public var operatorBillingHosts: [String]
    public var operatorDomains: [String]
    public var aggregators: [Aggregator]
    public var patterns: Patterns
}

// MARK: - cz-premium.json

public struct PremiumRules: Sendable, Decodable {
    public struct SMSRule: Sendable, Decodable {
        public var digits: Int
        public var pattern: String
        public var billing: String
        public var price: String?
        public var cs: String
        public var en: String
    }

    public struct SMS: Sendable, Decodable {
        public struct Charity: Sendable, Decodable {
            public var number: String
            public var recurringKeyword: String
        }

        public var categories: [String: LocalizedText]
        public var rules: [SMSRule]
        public var charity: Charity
        public var activationKeywords: [String]
    }

    public struct Voice: Sendable, Decodable {
        public var pricing: String
        public var price: String?
        public var cs: String
        public var en: String
    }

    public struct MMI: Sendable, Decodable {
        public var activation: [String]
        public var status: [String]
    }

    public var sms: SMS
    public var voice: [String: Voice]
    public var mmi: MMI
}

// MARK: - wangiri.json

public struct WangiriPrefix: Sendable, Decodable {
    public var cc: String
    public var cs: String
    public var en: String
}

struct WangiriFile: Decodable { var prefixes: [WangiriPrefix] }

// MARK: - keywords.json

public struct Keywords: Sendable, Decodable {
    public var urlContext: [String]
    public var safeAccountPhrases: [String]
    public var urgencyPhrases: [String]
    public var authPathFamilies: [String]
    public var tokenQueryKeys: [String]
    public var tokenQueryPrefixes: [String]
}

// MARK: - state-accounts.json

public struct StateAccountRules: Sendable, Decodable {
    public struct Institution: Sendable, Decodable {
        public var id: String
        public var name: LocalizedText
        public var patterns: [String]
    }

    public var bankCode: String
    public var institutions: [Institution]
    public var excluded: [String]
}

// MARK: - bank-codes-cz.json

public struct Bank: Sendable, Decodable, Hashable {
    public var name: String
    public var bic: String?
}

struct BanksFile: Decodable { var banks: [String: Bank] }

// MARK: - content

public struct OperatorGuide: Sendable, Decodable {
    public struct Operator: Sendable, Decodable {
        public var id: String?
        public var name: ArgValue
        public var verified: Bool?
        public var steps: [String: [String]]
    }

    public var intro: LocalizedText
    public var operators: [Operator]
    public var tips: [String: [String]]
}

public struct RecoveryGuide: Sendable, Decodable {
    public struct Section: Sendable, Decodable {
        public var title: LocalizedText
        public var steps: [String: [String]]
    }

    public var title: LocalizedText
    public var intro: LocalizedText
    public var sections: [Section]
    public var contacts: [String: [String]]
}
