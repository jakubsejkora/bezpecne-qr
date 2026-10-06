import BQCore
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BQServices

struct SharingTests {
    private func analysis(_ text: String = "https://example.org") -> Analysis {
        Analyzer().analyze(ScannedCode(text: text), options: AnalysisOptions(pageFetch: false, domainChecks: false, offline: true))
    }
    @Test func inboxV3DiagnosticsAndLegacyVersions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = HistoryInbox(directory: dir)
        try inbox.invalidate(enabled: true)
        let token = try #require(try inbox.begin())
        let a = analysis()
        let d = CheckDiagnostics(a, options: AnalysisOptions(pageFetch: false))
        for version in [1, 2, 3] {
            var entry = try #require(HistoryEnvelope(a, generation: token, diagnostics: version == 3 ? d : nil))
            entry.id = UUID(); entry.version = version
            try inbox.put(entry)
        }
        let entries = try inbox.entries()
        #expect(entries.count == 3)
        #expect(entries.first { $0.version == 3 }?.diagnostics == d)
        #expect(entries.filter { $0.version < 3 }.allSatisfy { $0.diagnostics == nil })
        var bad = try #require(HistoryEnvelope(a, generation: token, diagnostics: d))
        bad.id = UUID(); bad.diagnostics?.transportError = "private?token=secret"
        try inbox.put(bad)
        #expect(try inbox.entries().count == 3)
    }
    @Test func migrationPreservesExplicitChoicesAndRunsOnce() throws {
        let a = "migration-old-" + UUID().uuidString, b = "migration-new-" + UUID().uuidString
        let old = try #require(UserDefaults(suiteName: a)), shared = try #require(UserDefaults(suiteName: b))
        defer { old.removePersistentDomain(forName: a); shared.removePersistentDomain(forName: b) }
        old.set(false, forKey: SharedSettings.history); old.set(false, forKey: SharedSettings.pageFetch)
        old.set(true, forKey: "onboardingDone")
        shared.set("precision", forKey: SharedSettings.design)
        shared.set("circle", forKey: SharedSettings.aim)
        shared.set("perspectiveTrace", forKey: SharedSettings.capture)
        old.set(true, forKey: SharedSettings.domainChecks)
        shared.set(false, forKey: SharedSettings.domainChecks)
        SharedSettings.migrate(from: old, to: shared)
        #expect(!SharedSettings.enabled(SharedSettings.history, in: shared))
        #expect(!SharedSettings.enabled(SharedSettings.pageFetch, in: shared))
        #expect(!SharedSettings.enabled(SharedSettings.domainChecks, in: shared))
        #expect(shared.bool(forKey: SharedSettings.networkNotice))
        #expect(shared.string(forKey: SharedSettings.design) == "precision")
        #expect(shared.string(forKey: SharedSettings.aim) == "circle")
        #expect(shared.string(forKey: SharedSettings.capture) == "perspectiveTrace")
        shared.set("edgeRails", forKey: SharedSettings.aim)
        #expect(shared.string(forKey: SharedSettings.capture) == "perspectiveTrace")
        #expect(shared.string(forKey: SharedSettings.design) == "precision")
        shared.set(true, forKey: SharedSettings.pageFetch)
        SharedSettings.migrate(from: old, to: shared)
        #expect(SharedSettings.enabled(SharedSettings.pageFetch, in: shared))
    }
    @Test func inboxDeduplicatesAndRejectsLateWritesAfterClearOrDisable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = HistoryInbox(directory: dir)
        try inbox.invalidate(enabled: true)
        let token = try #require(try inbox.begin())
        let entry = try #require(HistoryEnvelope(analysis(), generation: token))
        try inbox.put(entry); try inbox.put(entry)
        #expect(try inbox.entries().count == 1)
        try inbox.invalidate(enabled: true)
        try inbox.put(entry)
        #expect(try inbox.entries().isEmpty)
        #expect(try inbox.begin() != token)
        try inbox.invalidate(enabled: false)
        #expect(try inbox.begin() == nil)
        try inbox.put(entry)
        #expect(try inbox.entries().isEmpty)
    }
    @Test func inboxRejectsSensitiveExpiredFutureAndUnknownVersions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = HistoryInbox(directory: dir)
        try inbox.invalidate(enabled: true)
        let token = try #require(try inbox.begin())
        #expect(HistoryEnvelope(analysis("otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP"), generation: token) == nil)
        var e = try #require(HistoryEnvelope(analysis(), generation: token))
        e.date = Date().addingTimeInterval(-8 * 24 * 3600); try inbox.put(e)
        e.date = Date().addingTimeInterval(3600); try inbox.put(e)
        e.date = Date(); e.version = 99; try inbox.put(e)
        e.version = 1; e.payload = "otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP"; try inbox.put(e)
        #expect(try inbox.entries().isEmpty)
        e = try #require(HistoryEnvelope(analysis(), generation: token)); try inbox.put(e)
        #expect(try inbox.entries(now: Date().addingTimeInterval(8 * 24 * 3600)).isEmpty)
        try Data("corrupt".utf8).write(to: dir.appendingPathComponent(UUID().uuidString + ".json"))
        #expect(try inbox.entries().isEmpty)
    }
    @Test func sharedImageScannerValidatesData() async throws {
        await #expect(throws: ImageScanError.self) { try await ImageCodeScanner.scan(Data("not an image".utf8)) }
        await #expect(throws: ImageScanError.self) { try await ImageCodeScanner.scan(Data(count: ImageCodeScanner.maxBytes + 1)) }
    }
    @Test func imageOrientationAndDownsamplingPreserveCodeGeometry() async throws {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("https://example.org/orientation".utf8)
        let qr = try #require(filter.outputImage)
        let scaled = qr.transformed(by: CGAffineTransform(scaleX: 12, y: 12)).transformed(by: CGAffineTransform(translationX: 150, y: 220))
        let canvas = scaled.composited(over: CIImage(color: .white)).cropped(to: CGRect(x: 0, y: 0, width: 800, height: 1100))
        let cg = try #require(CIContext().createCGImage(canvas, from: canvas.extent))
        var uprightBounds = CGRect.zero
        for orientation in [1, 3, 6, 8] {
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            let result = try await ImageCodeScanner.scan(data as Data)
            #expect(result.codes.count == 1)
            let code = try #require(result.codes.first)
            #expect(code.code.text == "https://example.org/orientation")
            #expect(code.region.corners.count == 4)
            #expect(code.region.bounds.minX >= 0 && code.region.bounds.maxX <= 1)
            #expect(code.region.bounds.minY >= 0 && code.region.bounds.maxY <= 1)
            #expect(result.image.width == (orientation >= 6 ? 1100 : 800))
            if orientation == 1 { uprightBounds = code.region.bounds }
            let b = uprightBounds
            let expected: CGRect = switch orientation {
            case 3: CGRect(x: 1 - b.maxX, y: 1 - b.maxY, width: b.width, height: b.height)
            case 6: CGRect(x: 1 - b.maxY, y: b.minX, width: b.height, height: b.width)
            case 8: CGRect(x: b.minY, y: 1 - b.maxX, width: b.height, height: b.width)
            default: b
            }
            #expect(abs(code.region.bounds.midX - expected.midX) < 0.02)
            #expect(abs(code.region.bounds.midY - expected.midY) < 0.02)
        }
    }
}
