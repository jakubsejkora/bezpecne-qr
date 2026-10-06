import BQCore
import Darwin
import Foundation

/// Only non-sensitive analyses may cross the extension boundary. No image is ever persisted.
public struct HistoryEnvelope: Codable, Sendable, Identifiable {
    public var version = 3
    public var id: UUID
    public var generation: UUID
    public var date: Date
    public var type: String
    public var band: String
    public var score: Int?
    public var symbology: String
    public var payload: String
    /// A canonical hostname only; resolved paths, queries and imagery are never added.
    public var resolvedHost: String?
    public var diagnostics: CheckDiagnostics?

    public init?(_ analysis: Analysis, generation: UUID, date: Date = Date(), diagnostics: CheckDiagnostics? = nil) {
        guard !analysis.isSensitive, analysis.code.text.utf8.count <= 65_536 else { return nil }
        id = analysis.id; self.generation = generation; self.date = date
        type = analysis.type.rawValue; band = analysis.band.rawValue; score = analysis.assessment.score
        symbology = analysis.code.symbology.rawValue; payload = analysis.code.text
        resolvedHost = analysis.resolvedHost
        self.diagnostics = diagnostics?.isValid == true ? diagnostics : nil
    }
}

/// A process-coordinated, bounded inbox. Tokens are captured BEFORE inspection, never at write time.
/// Files survive a failed database save; acknowledge only after a successful, idempotent import.
public struct HistoryInbox: Sendable {
    public let directory: URL
    public static var shared: HistoryInbox? {
        SharedSettings.container.map { HistoryInbox(directory: $0.appendingPathComponent("HistoryInbox", isDirectory: true)) }
    }
    public init(directory: URL) { self.directory = directory }
    private struct State: Codable { var generation = UUID(); var enabled = true }
    private let maxEntries = 100
    private let lifetime: TimeInterval = 7 * 24 * 3600

    public func begin() throws -> UUID? {
        try locked { let s = try state(); return s.enabled ? s.generation : nil }
    }
    public func invalidate(enabled: Bool) throws {
        try locked {
            try writeState(State(generation: UUID(), enabled: enabled))
            for url in try files() { try? FileManager.default.removeItem(at: url) }
        }
    }
    public func put(_ entry: HistoryEnvelope) throws {
        try locked {
            let s = try state()
            guard s.enabled, s.generation == entry.generation, valid(entry, state: s, now: Date()) else { return }
            _ = try readEntries(state: s, now: Date())
            let urls = try files().sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard urls.count < maxEntries || urls.contains(where: { $0.lastPathComponent == entry.id.uuidString + ".json" }) else { return }
            let data = try JSONEncoder().encode(entry)
            let url = directory.appendingPathComponent(entry.id.uuidString + ".json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
    public func entries(now: Date = Date()) throws -> [HistoryEnvelope] {
        try locked { try readEntries(state: state(), now: now) }
    }
    public func acknowledge(_ ids: [UUID]) throws {
        try locked { for id in ids { try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json")) } }
    }
    private func valid(_ e: HistoryEnvelope, state s: State, now: Date) -> Bool {
        guard s.enabled, [1, 2, 3].contains(e.version), e.generation == s.generation,
              e.date <= now.addingTimeInterval(60), now.timeIntervalSince(e.date) <= lifetime,
              e.payload.utf8.count <= 65_536 else { return false }
        // Recheck sensitivity at the trust boundary, including files created by older app versions.
        let a = Analyzer().analyze(ScannedCode(text: e.payload), options: AnalysisOptions(pageFetch: false, domainChecks: false, offline: true))
        if let host = e.resolvedHost {
            guard e.version >= 2, e.type == CodeType.url.rawValue, host.utf8.count <= 253,
                  host == DomainKit.asciiHost(host),
                  let url = URL(string: "https://" + host), url.host == host,
                  url.path.isEmpty, url.query == nil, url.fragment == nil, url.user == nil, url.port == nil,
                  case .fetch = LinkGate(rules: .bundled).evaluate(url, hop: 0) else { return false }
        }
        guard e.diagnostics == nil || (e.version >= 3 && e.diagnostics?.isValid == true) else { return false }
        return !a.isSensitive && a.type.rawValue == e.type && Band(rawValue: e.band) != nil
    }
    private func readEntries(state s: State, now: Date) throws -> [HistoryEnvelope] {
        var entries: [HistoryEnvelope] = []
        for url in try files() {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
            guard size <= 100_000, let data = try? Data(contentsOf: url),
                  let e = try? JSONDecoder().decode(HistoryEnvelope.self, from: data),
                  url.lastPathComponent == e.id.uuidString + ".json", valid(e, state: s, now: now) else {
                try? FileManager.default.removeItem(at: url); continue
            }
            entries.append(e)
        }
        return Array(entries.sorted { $0.date < $1.date }.suffix(maxEntries))
    }
    private func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "state.json" }
    }
    private func state() throws -> State {
        let url = directory.appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath: url.path) { return try JSONDecoder().decode(State.self, from: Data(contentsOf: url)) }
        let s = State(enabled: SharedSettings.enabled(SharedSettings.history))
        try writeState(s); return s
    }
    private func writeState(_ state: State) throws {
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtection])
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
