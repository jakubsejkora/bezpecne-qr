import SwiftUI

/// The idle camera guide is decorative. It never sets the detector's region of interest.
public enum AimGuideStyle: String, CaseIterable, Identifiable, Sendable {
    case roundedCorners, sharpCorners, thinSquare, roundedSquare, edgeRails, cornerDots, circle, none
    public var id: String { rawValue }
    public var title: String { L10n.t("aim." + rawValue, .preferred) }
}

private struct AimGuideKey: EnvironmentKey { static let defaultValue = AimGuideStyle.roundedCorners }
public extension EnvironmentValues {
    var bqAimGuideStyle: AimGuideStyle {
        get { self[AimGuideKey.self] }
        set { self[AimGuideKey.self] = newValue }
    }
}

/// Shared by the live scanner and the Design Lab thumbnails; no perpetual animation.
public struct AimGuide: View {
    private var selection: AimGuideStyle?
    @Environment(\.bqAimGuideStyle) private var preference
    public init(style: AimGuideStyle? = nil) { selection = style }
    public var body: some View {
        GeometryReader { geo in
            let style = selection ?? preference
            let side = min(geo.size.width, geo.size.height) * 0.86
            let rect = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2, width: side, height: side)
            let line = style == .thinSquare ? (side < 100 ? 1.2 : 1.5) : (side < 100 ? 1.8 : 2.5)
            if style != .none {
                AimPath(style: style, box: rect)
                    .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: style == .sharpCorners ? .square : .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.95), radius: 2)
                    .shadow(color: .black.opacity(0.65), radius: 0.5)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct AimPath: Shape {
    let style: AimGuideStyle
    let box: CGRect
    func path(in _: CGRect) -> Path {
        let r = box, side = box.width, arm = side * 0.22
        return Path { p in
            switch style {
            case .roundedCorners, .sharpCorners:
                let curve = style == .roundedCorners ? side * 0.07 : 0
                for (x, y, dx, dy) in [(r.minX,r.minY,1.0,1.0),(r.maxX,r.minY,-1.0,1.0),
                                       (r.maxX,r.maxY,-1.0,-1.0),(r.minX,r.maxY,1.0,-1.0)] {
                    p.move(to: CGPoint(x: x, y: y + dy * arm))
                    p.addLine(to: CGPoint(x: x, y: y + dy * curve))
                    p.addQuadCurve(to: CGPoint(x: x + dx * curve, y: y), control: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                }
            case .thinSquare: p.addRect(r)
            case .roundedSquare: p.addRoundedRect(in: r, cornerSize: CGSize(width: side * 0.13, height: side * 0.13))
            case .edgeRails:
                for y in [r.minY, r.maxY] {
                    p.move(to: CGPoint(x: r.midX - arm / 2, y: y)); p.addLine(to: CGPoint(x: r.midX + arm / 2, y: y))
                }
                for x in [r.minX, r.maxX] {
                    p.move(to: CGPoint(x: x, y: r.midY - arm / 2)); p.addLine(to: CGPoint(x: x, y: r.midY + arm / 2))
                }
            case .cornerDots:
                let diameter = max(3, side * 0.023)
                for x in [r.minX, r.maxX] { for y in [r.minY, r.maxY] {
                    p.addEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
                } }
            case .circle:
                p.addEllipse(in: r)
                for y in [r.minY, r.maxY] {
                    p.move(to: CGPoint(x: r.midX, y: y - side * 0.03)); p.addLine(to: CGPoint(x: r.midX, y: y + side * 0.03))
                }
                for x in [r.minX, r.maxX] {
                    p.move(to: CGPoint(x: x - side * 0.03, y: r.midY)); p.addLine(to: CGPoint(x: x + side * 0.03, y: r.midY))
                }
            case .none: break
            }
        }
    }
}
