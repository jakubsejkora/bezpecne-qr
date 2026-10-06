#if DEBUG || DESIGN_REVIEW
import BQCore
import BQServices
import BQUI
import CoreImage.CIFilterBuiltins
import SwiftUI

struct DesignLab: View {
    let flow: ScanFlow
    @AppStorage(SharedSettings.capture, store: SharedSettings.defaults) private var capture = "cameraCorners"
    @AppStorage(SharedSettings.scoreChart, store: SharedSettings.defaults) private var scoreChart = "spectrum"
    var body: some View {
        List {
            Section {
                NavigationLink { ScoreChartLab(flow: flow) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.t("scoreChart.title", .preferred), systemImage: "chart.bar.xaxis").font(.headline)
                        RiskScoreChart(score: 42, muted: false, style: ScoreChartStyle(rawValue: scoreChart) ?? .spectrum, compact: true)
                            .frame(height: 42)
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier("scoreChart.open")
            }
            Section {
                Picker(L10n.t("lab.capture", .preferred), selection: $capture) {
                    ForEach(CaptureStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                ForEach(CaptureExamples.Scene.allCases) { scene in
                    Button { CaptureExamples.replay(flow, scene: scene) } label: {
                        Label(L10n.t("lab.scene." + scene.rawValue, .preferred), systemImage: "play.circle")
                    }
                }
            } header: { Text(L10n.t("lab.afterDetection", .preferred)) }
              footer: { Text(L10n.t("lab.replayNote", .preferred)) }
            Section {
                NavigationLink { DebugSamplesScreen(flow: flow, close: {}) } label: {
                    Label(L10n.t("lab.results", .preferred), systemImage: "rectangle.stack")
                }
            }
        }.modifier(DesignListModifier()).navigationTitle(L10n.t("lab.title", .preferred))
    }
}

@MainActor enum CaptureExamples {
    enum Scene: String, CaseIterable, Identifiable {
        case single, multiple, tilted, small, edge, crowded
        var id: String { rawValue }
    }
    static func replay(_ flow: ScanFlow, multiple: Bool) { replay(flow, scene: multiple ? .multiple : .single) }
    static func replay(_ flow: ScanFlow, scene: Scene) {
        flow.onShowScanner?()
        let presentation = make(scene)
        flow.holdReplay(presentation, multiple: presentation.regions.count > 1)
        flow.replayScene = scene.rawValue
    }
    static func make(_ scene: Scene) -> CapturePresentation {
        let size = CGSize(width: 600, height: 1000)
        var regions: [CaptureRegion] = []
        let rects: [CGRect]
        switch scene {
        case .single, .tilted: rects = [CGRect(x: 145, y: 400, width: 310, height: 310)]
        case .multiple: rects = [CGRect(x: 62, y: 365, width: 205, height: 205), CGRect(x: 335, y: 510, width: 190, height: 190)]
        case .small: rects = [CGRect(x: 260, y: 495, width: 80, height: 80)]
        case .edge: rects = [CGRect(x: 2, y: 430, width: 155, height: 155), CGRect(x: 446, y: 660, width: 154, height: 154)]
        case .crowded: rects = [CGRect(x: 120, y: 400, width: 145, height: 145), CGRect(x: 273, y: 440, width: 140, height: 140), CGRect(x: 188, y: 596, width: 154, height: 154)]
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let c = context.cgContext
            UIColor(red: 0.23, green: 0.25, blue: 0.23, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.78, green: 0.78, blue: 0.71, alpha: 1).setFill()
            c.fill(CGRect(x: 32, y: 250, width: 536, height: 590))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: UIColor.darkGray]
            ("Bezpečné QR / " + L10n.t("lab.sample", .preferred) as NSString).draw(at: CGPoint(x: 58, y: 285), withAttributes: attrs)
            for (index, rect) in rects.enumerated() {
                let angle: CGFloat = scene == .tilted ? -0.16 : 0
                let center = CGPoint(x: rect.midX, y: rect.midY)
                c.saveGState(); c.translateBy(x: center.x, y: center.y); c.rotate(by: angle)
                let local = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
                UIColor.white.setFill(); c.fill(local.insetBy(dx: -10, dy: -10))
                if let qr = ActionHandler.qrImage("https://example.org/preview/\(index + 1)") {
                    c.interpolationQuality = .none; qr.draw(in: local)
                }
                c.restoreGState()
                let corners = [CGPoint(x: local.minX, y: local.minY), CGPoint(x: local.maxX, y: local.minY),
                               CGPoint(x: local.maxX, y: local.maxY), CGPoint(x: local.minX, y: local.maxY)].map { p in
                    CGPoint(x: (center.x + p.x * cos(angle) - p.y * sin(angle)) / size.width,
                            y: (center.y + p.x * sin(angle) + p.y * cos(angle)) / size.height)
                }
                regions.append(CaptureRegion(corners: corners))
            }
        }
        return CapturePresentation(image: image, regions: regions)
    }
}
#endif
