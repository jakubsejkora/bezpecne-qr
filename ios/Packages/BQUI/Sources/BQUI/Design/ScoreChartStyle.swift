import BQCore
import SwiftUI

/// Presentation only: every chart uses the same 0–100 risk scale and palette.
public enum ScoreChartStyle: String, CaseIterable, Identifiable, Sendable {
    case spectrum, rail, bands, ticks, dots, arc
    public var id: String { rawValue }
    public var title: String { L10n.t("scoreChart." + rawValue, .preferred) }
    public var descriptionText: String { L10n.t("scoreChart." + rawValue + ".description", .preferred) }
}

private struct ScoreChartKey: EnvironmentKey { static let defaultValue = ScoreChartStyle.spectrum }
public extension EnvironmentValues {
    var bqScoreChart: ScoreChartStyle {
        get { self[ScoreChartKey.self] }
        set { self[ScoreChartKey.self] = newValue }
    }
}

/// The numeric score and qualification belong to the header; the chart is decorative for VoiceOver.
/// Its marker stays visible in monochrome, so position never depends on colour alone.
public struct RiskScoreChart: View {
    private let score: Int
    private let muted: Bool
    private let override: ScoreChartStyle?
    private let compact: Bool
    private let slim: Bool
    @Environment(\.bqScoreChart) private var selection
    @Environment(\.bqDesign) private var design

    public init(score: Int, muted: Bool, style: ScoreChartStyle? = nil, compact: Bool = false, slim: Bool = false) {
        self.score = score; self.muted = muted; self.override = style
        self.compact = compact; self.slim = slim
    }
    private var style: ScoreChartStyle { override ?? selection }
    private var fraction: CGFloat { CGFloat(min(100, max(0, score))) / 100 }

    public var body: some View {
        Group {
            if style == .arc { arc }
            else { linear }
        }
        .accessibilityHidden(true)
        // Switching a review style never animates an apparent change in risk.
        .transaction { $0.animation = nil }
    }

    private var linear: some View {
        GeometryReader { geo in
            let inset: CGFloat = style == .spectrum ? 0 : 8
            let width = max(1, geo.size.width - inset * 2)
            let x = min(geo.size.width - 7, max(7, inset + width * fraction))
            let height: CGFloat = style == .rail ? 5 : style == .spectrum ? (slim ? 6 : 18) : 18
            ZStack {
                Group {
                    if style == .dots {
                        ForEach(0...20, id: \.self) { index in
                            Circle().fill(SignalPalette.color(at: index * 5).color)
                                .frame(width: min(7, width / 28), height: min(7, width / 28))
                                .position(x: inset + CGFloat(index) * width / 20, y: geo.size.height / 2)
                        }
                    } else if style == .ticks {
                        ForEach(0...50, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(SignalPalette.color(at: index * 2).color)
                                .frame(width: min(2.5, width / 80), height: index % 5 == 0 ? height : height * 0.65)
                                .position(x: inset + CGFloat(index) * width / 50, y: geo.size.height / 2)
                        }
                    } else {
                        SignalPalette.gradient.mask(ChartTrack(style: style))
                            .frame(width: width, height: height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }.grayscale(muted ? 1 : 0)
                if style == .rail || style == .dots {
                    Circle().fill(.white).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.black, lineWidth: 2))
                        .position(x: x, y: geo.size.height / 2)
                } else {
                    Capsule().fill(.white).frame(width: 6, height: style == .spectrum ? 14 : 24)
                        .overlay(Capsule().stroke(.black, lineWidth: 2))
                        .position(x: x, y: geo.size.height / 2)
                }
            }
        }.frame(height: style == .spectrum ? 18 : 28)
    }

    private var arc: some View {
        let height: CGFloat = compact ? 56 : 88
        return GeometryReader { geo in
            // A shallow 120° arc leaves room for the destination and rescan control.
            let radius = min((geo.size.width - 24) / 1.733, (height - 22) * 2)
            let center = CGPoint(x: geo.size.width / 2, y: radius + 7)
            let markerAngle = Double.pi * (210 + Double(fraction) * 120) / 180
            Canvas { context, _ in
                var path = Path()
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(210), endAngle: .degrees(330), clockwise: false)
                // Pad before the start angle so the rounded green cap never crosses the
                // conic gradient's red-to-green wrap seam.
                let stops = [Gradient.Stop(color: SignalPalette.color(at: 0).color, location: 0)] + SignalPalette.gradientStops.map {
                    Gradient.Stop(color: $0.color, location: (5 + $0.location * 120) / 360)
                } + [.init(color: SignalPalette.color(at: 100).color, location: 1)]
                context.stroke(path, with: .conicGradient(Gradient(stops: stops), center: center, angle: .degrees(205)),
                               style: StrokeStyle(lineWidth: compact ? 6 : 9, lineCap: .round))
            }.grayscale(muted ? 1 : 0)
            Circle().fill(.white).frame(width: compact ? 10 : 14, height: compact ? 10 : 14)
                .overlay(Circle().stroke(.black, lineWidth: 2))
                .position(x: center.x + radius * cos(markerAngle), y: center.y + radius * sin(markerAngle))
            if !compact {
                HStack {
                    Text("0")
                    Spacer()
                    Text("100")
                }.font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(design.ink)
                    .frame(width: radius * 1.733 + 12)
                    .position(x: center.x, y: center.y - radius / 2 + 10)
            }
        }.frame(height: height)
    }
}

private struct ChartTrack: Shape {
    let style: ScoreChartStyle
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch style {
        case .spectrum:
            path.addRect(rect)
        case .rail, .arc:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
        case .bands:
            // These are the actual safe/caution/danger boundaries, not equal-sized invented bands.
            let boundaries: [CGFloat] = [0, 0.25, 0.60, 1]
            for index in 0..<3 {
                let start = rect.minX + boundaries[index] * rect.width + (index == 0 ? 0 : 2)
                let end = rect.minX + boundaries[index + 1] * rect.width - (index == 2 ? 0 : 2)
                path.addRoundedRect(in: CGRect(x: start, y: rect.minY, width: max(0, end - start), height: rect.height),
                                    cornerSize: CGSize(width: 3, height: 3))
            }
        case .ticks, .dots:
            // These discrete tracks are drawn with sampled colours above.
            break
        }
        return path
    }
}
