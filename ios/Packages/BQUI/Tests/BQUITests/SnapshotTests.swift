import BQCore
import SwiftUI
import Testing
import UIKit
@testable import BQUI

/// Renders the result sheet for the corpus with `ImageRenderer` (393 pt wide, unconstrained
/// height) and writes PNGs to ios/build/ui-snapshots/ for visual review. These are review
/// artefacts, not pixel assertions; the tests fail only if a view can't be rendered.
@MainActor
@Suite(.serialized)
struct SnapshotTests {
    nonisolated static let output = Corpus.root.appendingPathComponent("ios/build/ui-snapshots")
    nonisolated static let width: CGFloat = 393

    /// Key samples also rendered in dark mode and at the largest accessibility text size.
    nonisolated static let keySamples = [
        "url-parking-fake", "url-dcb-subscription", "url-menu-shortener", "url-idn-lookalike", "url-long-domain",
        "spd-basic", "spd-standing-order", "sms-premium-ano", "tel-mmi-forward", "vcard-business",
        "wifi-wpa2", "otpauth-migration", "event-concert", "geo-point", "bcbp-boarding",
    ]

    @Test("Every corpus sample (cs, light)", arguments: Corpus.ids)
    func light(_ id: String) throws {
        try render(ResultScreen(model: model(id)), "light/\(id)")
    }

    @Test("Every corpus sample with details expanded (cs, light)", arguments: Corpus.ids)
    func details(_ id: String) throws {
        let m = model(id)
        m.detailsExpanded = true
        m.contactMoreExpanded = true
        try render(ResultScreen(model: m), "details/\(id)")
    }

    @Test("Key samples in dark mode", arguments: keySamples)
    func dark(_ id: String) throws {
        try render(ResultScreen(model: model(id)), "dark/\(id)", scheme: .dark)
    }

    @Test("Key samples at accessibility text size AX5", arguments: keySamples)
    func accessibility(_ id: String) throws {
        try render(ResultScreen(model: model(id)), "ax5/\(id)", typeSize: .accessibility5)
    }

    @Test("Key samples in English", arguments: ["url-parking-fake", "spd-basic", "tel-mmi-forward", "wifi-wpa2"])
    func english(_ id: String) throws {
        try render(ResultScreen(model: model(id, language: .en)), "en/\(id)")
    }

    @Test("Checking state (shortener, two redirects so far)")
    func checking() throws {
        let m = ResultModel(analysis: Corpus.pendingAnalysis("url-menu-shortener"), fromCamera: true, language: .cs)
        #expect(m.isChecking, "a pending inspection starts in the checking state")
        m.step = .address
        m.step = .domain
        m.step = .redirects(1)
        m.step = .redirects(2)
        try render(ResultScreen(model: m), "states/checking")
        try render(ResultScreen(model: m), "states/checking-dark", scheme: .dark)
    }

    @Test("Decisive danger is shown while the check continues")
    func decisiveDanger() throws {
        // E.g. a reviewed blocklist hit is known before the page check finishes.
        let m = ResultModel(analysis: Corpus.analysis("url-parking-fake"), fromCamera: true, language: .cs)
        m.isChecking = true
        m.step = .redirects(1)
        m.step = .page
        try render(ResultScreen(model: m), "states/decisive-danger-while-checking")
    }

    @Test("Page extract of url-dcb-subscription")
    func pageExtract() throws {
        let m = model("url-dcb-subscription")
        m.route = .pageExtract
        try render(ResultScreen(model: m), "states/page-extract")
        try render(ResultScreen(model: m), "states/page-extract-dark", scheme: .dark)
        try render(ResultScreen(model: m), "states/page-extract-ax5", typeSize: .accessibility5)
    }

    @Test("Chooser for scene-two-codes")
    func chooser() throws {
        let scenario = try #require(Corpus.scenarios.first { $0.id == "scene-two-codes" })
        let candidates = scenario.children.map(Corpus.analysis)
        let view = ChooserView(candidates: candidates, language: .cs, onPick: { _ in }, onClose: {})
        try render(view, "states/chooser")
        try render(view, "states/chooser-dark", scheme: .dark)
        try render(view, "states/chooser-ax5", typeSize: .accessibility5)
    }

    @Test("Contact saved, Wi‑Fi password revealed, toast")
    func interactionStates() throws {
        let contact = model("vcard-business")
        contact.finish(.addContact, .done(toast: "Uloženo v Kontaktech"))
        try render(ResultScreen(model: contact), "states/contact-saved")

        let wifi = model("wifi-wpa2")
        wifi.revealPassword = true
        try render(ResultScreen(model: wifi), "states/wifi-password-revealed")

        let copied = model("spd-basic")
        copied.finish(.copy("19-2000145399/0800", .account), .done(toast: "Zkopírováno"))
        try render(ResultScreen(model: copied), "states/payment-copied-toast")
    }

    // MARK: Rendering

    private func model(_ id: String, language: Language = .cs) -> ResultModel {
        ResultModel(analysis: Corpus.analysis(id), fromCamera: true, language: language)
    }

    private func render<V: View>(_ view: V, _ name: String, scheme: ColorScheme = .light,
                                 typeSize: DynamicTypeSize = .large) throws {
        let content = view
            .environment(\.bqSnapshot, true)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.locale, Locale(identifier: "cs_CZ"))
            .frame(width: Self.width)
            .background(BQColor.background)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        renderer.scale = 2
        var image = try #require(renderer.uiImage, "\(name) could not be rendered")
        if image.size.height * renderer.scale > 8_000 {
            // Very tall renders (AX5) exceed the PNG encoder's limits at @2x.
            renderer.scale = 1
            image = try #require(renderer.uiImage, "\(name) could not be rendered")
        }
        let data = try #require(image.pngData(), "\(name) could not be encoded")
        let url = Self.output.appendingPathComponent(name + ".png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        #expect(image.size.width == Self.width)
        #expect(image.size.height > 200, "\(name) rendered suspiciously short (\(image.size.height) pt)")
        // L10nTests deliberately asks for "does.not.exist"; tests run in parallel and share the set.
        let missing = L10n.missingKeys.subtracting(["does.not.exist"])
        #expect(missing.isEmpty, "\(name) asked for missing strings: \(missing.sorted())")
    }
}
