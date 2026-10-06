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

    @Test("All app designs render the full corpus", arguments: DesignDirection.allCases, Corpus.ids)
    func directions(_ design: DesignDirection, _ id: String) throws {
        try render(ResultScreen(model: model(id)).environment(\.bqDesign, design), "designs/\(design.rawValue)/\(id)")
    }

    @Test("Designs support dark, compact and accessibility layouts", arguments: DesignDirection.allCases)
    func designAccessibility(_ design: DesignDirection) throws {
        for id in ["url-parking-fake", "spd-basic", "wifi-wpa2"] {
            try render(ResultScreen(model: model(id, language: .en)).environment(\.bqDesign, design), "designs/\(design.rawValue)/dark-en-\(id)", scheme: .dark)
            try render(ResultScreen(model: model(id)).environment(\.bqDesign, design)
                ,
                "designs/\(design.rawValue)/ax5-\(id)", typeSize: .accessibility5)
        }
    }

    @Test("Every capture style renders every geometry", arguments: CaptureStyle.allCases, 0..<6)
    func captureStyles(_ style: CaptureStyle, _ scene: Int) throws {
        let size = CGSize(width: 390, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.darkGray.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); ctx.fill(CGRect(x: 100, y: 200, width: 150, height: 150))
        }
        let rects: [CGRect] = switch scene {
        case 1: [CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.25), CGRect(x: 0.6, y: 0.5, width: 0.25, height: 0.25)]
        case 3: [CGRect(x: 0.46, y: 0.5, width: 0.08, height: 0.08)]
        case 4: [CGRect(x: 0, y: 0.3, width: 0.2, height: 0.2), CGRect(x: 0.8, y: 0.7, width: 0.2, height: 0.2)]
        case 5: (0..<8).map { CGRect(x: 0.1 + Double($0 % 4) * 0.19, y: 0.4 + Double($0 / 4) * 0.17, width: 0.16, height: 0.15) }
        default: [CGRect(x: 0.25, y: 0.3, width: 0.4, height: 0.3)]
        }
        let regions = scene == 2 ? [CaptureRegion(corners: [CGPoint(x: 0.2, y: 0.4), CGPoint(x: 0.6, y: 0.3), CGPoint(x: 0.7, y: 0.6), CGPoint(x: 0.3, y: 0.7)])] : rects.map { CaptureRegion(rect: $0) }
        try render(CapturePreview(CapturePresentation(image: image, regions: regions)).frame(height: 600)
            .environment(\.bqCaptureStyle, style), "captures/\(style.rawValue)-\(scene)")
    }

    // MARK: Rendering

    @Test("Eight independent camera guides", arguments: AimGuideStyle.allCases)
    func aimingGuides(_ style: AimGuideStyle) throws {
        try render(AimGuide(style: style).frame(height: 300).padding(20).background(.black), "aims/\(style.rawValue)")
    }

    @Test("Signal risk states in both languages and appearances", arguments: [
        "url-menu-shortener", "url-free-hosting", "url-parking-fake", "url-offline-menu", "sms-premium-ano", "wifi-wpa2"
    ])
    func signalStates(_ id: String) throws {
        for lang in [Language.cs, .en] {
            let m = model(id, language: lang)
            for dark in [false, true] {
                try render(ResultScreen(model: m).environment(\.bqDesign, .signal),
                           "signal/\(id)-\(lang.rawValue)-\(dark ? "dark" : "light")", scheme: dark ? .dark : .light, width: 375)
            }
        }
        let m = model(id)
        m.moreActionsExpanded = true
        try render(ResultScreen(model: m).environment(\.bqDesign, .signal),
                   "signal/\(id)-accessible-options", typeSize: .accessibility5, width: 375)
        m.capabilities = .imageExtension
        try render(ResultScreen(model: m).environment(\.bqDesign, .signal), "signal/\(id)-extension", width: 375)
    }

    @Test("Signal presets across formats, risk states, languages and appearances", arguments: SignalPreset.allCases)
    func signalPresetMatrix(_ preset: SignalPreset) throws {
        let cases = ["url-menu-shortener", "url-free-hosting", "url-parking-fake", "url-offline-menu", "sms-premium-ano", "wifi-wpa2"]
        for style in ResultPresentationStyle.allCases {
            let layout: ResultScreen.Layout = style == .popup ? .popup : style == .sheet ? .summary : .full
            for id in cases {
                for language in [Language.cs, .en] {
                    for dark in [false, true] {
                        try render(ResultScreen(model: model(id, language: language), layout: layout)
                            .environment(\.bqSignalPreset, preset),
                            "review7/\(preset.rawValue)/\(style.rawValue)-\(id)-\(language.rawValue)-\(dark ? "dark" : "light")",
                            scheme: dark ? .dark : .light, width: 375)
                    }
                }
            }
        }
        for id in cases {
            try render(ResultScreen(model: model(id)).environment(\.bqSignalPreset, preset),
                "review7/\(preset.rawValue)/ax5-\(id)", typeSize: .accessibility5, width: 375)
            let m = model(id); m.capabilities = .imageExtension
            try render(ResultScreen(model: m).environment(\.bqSignalPreset, preset), "review7/\(preset.rawValue)/extension-\(id)")
        }
        try render(SignalScannerHeading().measureFadeHeader().frame(minHeight: 250).scannerFadeBackground()
            .environment(\.bqSignalPreset, preset).background(.black),
            "review7/\(preset.rawValue)/scanner")
    }

    @Test("Score charts preserve risk states and accessible layouts", arguments: ScoreChartStyle.allCases)
    func scoreCharts(_ style: ScoreChartStyle) throws {
        for id in ["url-menu-shortener", "url-free-hosting", "url-parking-fake", "url-offline-menu", "sms-premium-ano", "wifi-wpa2"] {
            for dark in [false, true] {
                let m = model(id, language: dark ? .en : .cs)
                try render(ResultScreen(model: m, layout: .summary)
                    .environment(\.bqSignalPreset, .poster).environment(\.bqScoreChart, style),
                    "score-charts/\(style.rawValue)/\(id)-\(dark ? "dark-en" : "light-cs")", scheme: dark ? .dark : .light, width: 375)
            }
        }
        for preset in SignalPreset.allCases {
            try render(ResultScreen(model: model("url-free-hosting"), layout: .popup)
                .environment(\.bqSignalPreset, preset).environment(\.bqScoreChart, style),
                "score-charts/\(style.rawValue)/\(preset.rawValue)-popup", width: 320)
        }
        let m = model("url-offline-menu"); m.capabilities = .imageExtension
        try render(ResultScreen(model: m).environment(\.bqScoreChart, style),
                   "score-charts/\(style.rawValue)/extension-ax5", typeSize: .accessibility5, width: 320)
        try render(VStack(spacing: 24) {
            ForEach([0, 24, 25, 59, 60, 100], id: \.self) { score in
                Text("\(score)/100").font(.headline)
                RiskScoreChart(score: score, muted: false, style: style)
                RiskScoreChart(score: score, muted: true, style: style)
            }
        }.padding(24), "score-charts/\(style.rawValue)/endpoints")
    }

    @Test("Continuous Fade across presentations, risk states, languages and appearances", arguments: FadeTreatment.allCases)
    func fadeMatrix(_ treatment: FadeTreatment) throws {
        let cases = ["url-menu-shortener", "url-free-hosting", "url-parking-fake", "url-offline-menu", "sms-premium-ano", "wifi-wpa2"]
        for style in ResultPresentationStyle.allCases {
            let layout: ResultScreen.Layout = style == .popup ? .popup : style == .sheet ? .summary : .full
            for id in cases {
                for language in [Language.cs, .en] {
                    for dark in [false, true] {
                        try render(ResultScreen(model: model(id, language: language), layout: layout)
                            .environment(\.bqSignalPreset, .fade).environment(\.bqFadeTreatment, treatment),
                            "fade/\(treatment.rawValue)/\(style.rawValue)-\(id)-\(language.rawValue)-\(dark ? "dark" : "light")",
                            scheme: dark ? .dark : .light, width: 375)
                    }
                }
            }
        }
        for id in cases + ["url-long-domain", "spd-basic"] {
            try render(ResultScreen(model: model(id)).environment(\.bqSignalPreset, .fade).environment(\.bqFadeTreatment, treatment),
                       "fade/\(treatment.rawValue)/ax5-\(id)", typeSize: .accessibility5, width: 320)
            let m = model(id); m.capabilities = .imageExtension
            try render(ResultScreen(model: m).environment(\.bqSignalPreset, .fade).environment(\.bqFadeTreatment, treatment),
                       "fade/\(treatment.rawValue)/extension-\(id)", width: 375)
        }
        for bright in [false, true] {
            try render(VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        HStack { Spacer(); Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.padding(.horizontal, 22)
                        SignalScannerHeading()
                    }.measureFadeHeader()
                    Spacer()
                    AimGuide().frame(width: 230, height: 230)
                    Spacer()
                }.frame(height: 650).scannerFadeBackground().background(bright ? .white : .black)
                    .environment(\.bqSignalPreset, .fade).environment(\.bqFadeTreatment, treatment),
                    "fade/\(treatment.rawValue)/camera-\(bright)", width: 375)
        }
    }

    private func model(_ id: String, language: Language = .cs) -> ResultModel {
        ResultModel(analysis: Corpus.analysis(id), fromCamera: true, language: language)
    }

    private func render<V: View>(_ view: V, _ name: String, scheme: ColorScheme = .light,
                                 typeSize: DynamicTypeSize = .large, width: CGFloat = Self.width) throws {
        let content = view
            .environment(\.bqSnapshot, true)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.locale, Locale(identifier: "cs_CZ"))
            .frame(width: width)
            .background(BQColor.background)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
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
        #expect(image.size.width == width)
        #expect(image.size.height > 200, "\(name) rendered suspiciously short (\(image.size.height) pt)")
        // L10nTests deliberately asks for "does.not.exist"; tests run in parallel and share the set.
        let missing = L10n.missingKeys.subtracting(["does.not.exist"])
        #expect(missing.isEmpty, "\(name) asked for missing strings: \(missing.sorted())")
    }
}
