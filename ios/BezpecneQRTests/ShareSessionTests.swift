import BQCore
import BQServices
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import BezpecneQR

extension ScanLifecycleTests {
    private func localPreferences() {
        SharedSettings.defaults.set(true, forKey: SharedSettings.networkNotice)
        SharedSettings.defaults.set(false, forKey: SharedSettings.pageFetch)
        SharedSettings.defaults.set(false, forKey: SharedSettings.domainChecks)
    }
    private func provider(_ payloads: [String]) throws -> (NSItemProvider, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 600)).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
            for (i, text) in payloads.enumerated() {
                c.cgContext.interpolationQuality = .none
                ActionHandler.qrImage(text)?.draw(in: CGRect(x: 60 + i * 480, y: 120, width: 350, height: 350))
            }
        }
        let png = try #require(image.pngData())
        try png.write(to: url)
        let artifact = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/share-fixtures/\(payloads.count).png")
        try FileManager.default.createDirectory(at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: artifact)
        let p = NSItemProvider()
        p.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil); return nil
        }
        return (p, url)
    }
    private func waitForRead(_ session: ShareSession) async throws {
        for _ in 0..<500 {
            if !session.loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Image provider did not finish in five seconds")
    }
    @Test func oneImageProducesSameAnalysisAndClosePurgesCapture() async throws {
        localPreferences()
        let (p, url) = try provider(["https://example.org/share"])
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try await ProviderImage.load(p)
        #expect(data.count > 0)
        let decoded = try await ImageCodeScanner.scan(data)
        #expect(!decoded.codes.isEmpty)
        let session = ShareSession(close: {})
        session.load([p]); try await waitForRead(session)
        #expect(session.error == nil, "Unexpected share error: \(session.error ?? "none")")
        #expect(session.result?.analysis.code.text == "https://example.org/share")
        #expect(session.result?.capabilities == .imageExtension)
        #expect(session.capture != nil)
        #expect(session.result?.analysis.assessment == Analyzer().analyze(ScannedCode(text: "https://example.org/share"), options: AnalysisOptions(pageFetch: false, domainChecks: false)).assessment)
        session.cancel(); #expect(session.capture == nil); #expect(session.result == nil)
    }
    @Test func multiCodeWaitsForSelectionAndSensitiveImageIsDiscarded() async throws {
        localPreferences()
        let (p, url) = try provider(["Plain text", "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP"])
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ShareSession(close: {})
        session.load([p]); try await waitForRead(session)
        #expect(session.result == nil)
        #expect(session.candidates.count == 2)
        #expect(session.capture == nil)
        let sensitiveIndex = session.candidates.firstIndex { $0.isSensitive }
        let sensitive = try #require(sensitiveIndex)
        session.choose(sensitive)
        #expect(session.result?.analysis.isSensitive == true)
        #expect(session.capture == nil)
        session.cancel()
    }
    @Test func emptyImageAndMultipleAttachmentsAreExplicit() async throws {
        localPreferences()
        let (p, url) = try provider([])
        defer { try? FileManager.default.removeItem(at: url) }
        let multiple = ShareSession(close: {}); multiple.load([p, p])
        #expect(multiple.error != nil); #expect(!multiple.loading)
        let empty = ShareSession(close: {}); empty.load([p]); try await waitForRead(empty)
        #expect(empty.error != nil); #expect(empty.result == nil)
        empty.cancel(); multiple.cancel()
    }
    @Test func dismissalDropsLateProviderCallback() async throws {
        localPreferences()
        let (p, url) = try provider(["https://example.org/late"])
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ShareSession(close: {})
        session.load([p]); session.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.result == nil); #expect(session.capture == nil); #expect(session.candidates.isEmpty)
    }
}
