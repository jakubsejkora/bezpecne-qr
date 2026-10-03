import BQCore
import Foundation
import SwiftData

/// Settings keys (UserDefaults / @AppStorage).
enum SettingsKey {
    static let historyEnabled = "historyEnabled"
    static let pageFetch = "pageFetch"
    static let domainChecks = "domainChecks"
    static let onboardingDone = "onboardingDone"
}

extension UserDefaults {
    func bool(_ key: String, default value: Bool) -> Bool {
        object(forKey: key) == nil ? value : bool(forKey: key)
    }
}

// MARK: - Schema (versioned from day one)

enum HistorySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ScanRecord.self] }

    /// One scan in the local history. Sensitive codes keep only a redacted summary: `payload` is nil.
    @Model
    final class ScanRecord {
        var id: UUID
        var date: Date
        var type: String
        var band: String
        var score: Int?
        /// What the row shows: host, account, network name… — never a secret.
        var title: String
        var symbology: String
        var source: String
        /// The scanned content, so the scan can be checked again. Nil for sensitive codes.
        var payload: String?

        init(id: UUID, date: Date, type: String, band: String, score: Int?, title: String, symbology: String, source: String, payload: String?) {
            self.id = id
            self.date = date
            self.type = type
            self.band = band
            self.score = score
            self.title = title
            self.symbology = symbology
            self.source = source
            self.payload = payload
        }
    }
}

typealias ScanRecord = HistorySchemaV1.ScanRecord

enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum HistoryStore {
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration("History", schema: Schema(versionedSchema: HistorySchemaV1.self),
                                               isStoredInMemoryOnly: false, allowsSave: true, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: Schema(versionedSchema: HistorySchemaV1.self),
                                               migrationPlan: HistoryMigrationPlan.self, configurations: configuration) {
            return container
        }
        // A broken store must never stop scanning: fall back to memory.
        let memory = ModelConfiguration("History", schema: Schema(versionedSchema: HistorySchemaV1.self), isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Schema(versionedSchema: HistorySchemaV1.self), configurations: memory)
    }

    /// Adds (or updates) the record for an analysis. Called when the verdict is final.
    @MainActor
    static func save(_ analysis: Analysis, in context: ModelContext) {
        guard UserDefaults.standard.bool(SettingsKey.historyEnabled, default: true) else { return }
        let id = analysis.id
        let existing = try? context.fetch(FetchDescriptor<ScanRecord>(predicate: #Predicate { $0.id == id })).first
        let record = existing ?? ScanRecord(id: id, date: Date(), type: analysis.type.rawValue, band: analysis.band.rawValue,
                                            score: analysis.assessment.score, title: title(for: analysis),
                                            symbology: analysis.code.symbology.rawValue, source: analysis.code.source.rawValue,
                                            payload: analysis.isSensitive ? nil : analysis.code.text)
        record.band = analysis.band.rawValue
        record.score = analysis.assessment.score
        if existing == nil { context.insert(record) }
        try? context.save()
    }

    @MainActor
    static func clear(in context: ModelContext) {
        try? context.delete(model: ScanRecord.self)
        try? context.save()
    }

    /// A short, non-secret label for the history row.
    static func title(for analysis: Analysis) -> String {
        if analysis.isSensitive {
            switch analysis.content {
            case .wifi(let w): return w.ssid
            case .otp(let o): return o.issuer
            case .login(let l): return l.service
            default: return ""
            }
        }
        switch analysis.content {
        case .link(let l): return l.hostDisplay ?? l.host
        case .store(let s): return s.appId.map { "\(s.store) · \($0)" } ?? s.store
        case .messenger(let m): return "\(m.service) · \(m.target)"
        case .payment(let p): return [p.domestic ?? Format.iban(p.iban), p.amount.flatMap { Format.money($0, currency: p.currency, language: .preferred) }].compactMap { $0 }.joined(separator: " · ")
        case .invoice(let i): return i.id ?? "SID"
        case .transfer(let t): return t.name ?? t.creditor ?? Format.iban(t.iban)
        case .crypto(let c): return c.network
        case .sms(let s): return s.numberDisplay
        case .phone(let p): return p.numberDisplay
        case .email(let e): return e.to
        case .contact(let c): return c.name
        case .event(let e): return e.summary
        case .geo(let g): return g.label ?? "\(g.lat), \(g.lon)"
        case .text(let t): return String(t.text.prefix(60))
        case .intent(let i): return i.host ?? i.package ?? "intent"
        case .appInstall(let a): return a.host ?? "itms-services"
        case .gs1(let g): return "GTIN \(g.gtin)"
        case .emvco(let e): return e.merchant ?? "EMVCo"
        case .dataURI(let d): return d.mime
        default: return analysis.type.rawValue
        }
    }
}
