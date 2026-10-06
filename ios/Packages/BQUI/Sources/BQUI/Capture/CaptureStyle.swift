import BQCore
import SwiftUI
import UIKit

public enum CaptureStyle: String, CaseIterable, Identifiable, Sendable {
    case cameraCorners, fineOutline, perspectiveTrace, cornerAnchors, focusRails, softSpotlight
    case frostedSurround, glassCaption, numberedPins, liftedTile, thumbnailDock, captureToCard
    public var id: String { rawValue }
    public var title: String { L10n.t("capture." + rawValue, .preferred) }
    public var usesThumbnail: Bool { [.liftedTile, .thumbnailDock, .captureToCard].contains(self) }
}

/// Immutable presentation data, retained only for the current non-sensitive scan.
public struct CapturePresentation: @unchecked Sendable {
    public let image: UIImage
    public let regions: [CaptureRegion]
    public let selected: UUID?
    public init(image: UIImage, regions: [CaptureRegion], selected: UUID? = nil) {
        self.image = image; self.regions = regions; self.selected = selected
    }
    public var shownRegions: [CaptureRegion] {
        selected.map { id in regions.filter { $0.id == id } } ?? regions
    }
}
private struct CaptureStyleKey: EnvironmentKey { static let defaultValue = CaptureStyle.cameraCorners }
private struct CaptureKey: EnvironmentKey { static let defaultValue: CapturePresentation? = nil }
public extension EnvironmentValues {
    var bqCaptureStyle: CaptureStyle { get { self[CaptureStyleKey.self] } set { self[CaptureStyleKey.self] = newValue } }
    var bqCapture: CapturePresentation? { get { self[CaptureKey.self] } set { self[CaptureKey.self] = newValue } }
}

public struct CapturePreview: View {
    let presentation: CapturePresentation
    @Environment(\.bqCaptureStyle) private var style
    var fill: Bool
    var bottomInset: CGFloat
    public init(_ presentation: CapturePresentation, fill: Bool = false, bottomInset: CGFloat = 0) { self.presentation = presentation; self.fill = fill; self.bottomInset = bottomInset }
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                Image(uiImage: presentation.image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                CaptureOverlay(presentation, fill: fill, bottomInset: bottomInset).id(style.rawValue + (presentation.regions.first?.id.uuidString ?? ""))
            }.clipped()
        }.accessibilityHidden(true)
    }
}

/// All styles consume the SAME geometry and never change when or which code gets checked.
public struct CaptureOverlay: View {
    let presentation: CapturePresentation
    let fill: Bool
    let bottomInset: CGFloat
    @Environment(\.bqCaptureStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.bqSnapshot) private var snapshot
    @State private var settled = false
    public init(_ presentation: CapturePresentation, fill: Bool = true, bottomInset: CGFloat = 0) { self.presentation = presentation; self.fill = fill; self.bottomInset = bottomInset }
    public var body: some View {
        GeometryReader { geo in
            let regions = presentation.shownRegions
            let rects = regions.map { bounds($0.points(in: geo.size, image: presentation.image.size, fill: fill)) }
            ZStack {
                if style == .softSpotlight || style == .frostedSurround {
                    if style == .frostedSurround && !opaque {
                        Image(uiImage: presentation.image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                            .frame(width: geo.size.width, height: geo.size.height).blur(radius: 12)
                            .overlay(.black.opacity(0.16))
                            .mask(Apertures(rects: rects).fill(style: FillStyle(eoFill: true)))
                    } else {
                        Apertures(rects: rects).fill(.black.opacity(0.52), style: FillStyle(eoFill: true))
                    }
                }
                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    let points = region.points(in: geo.size, image: presentation.image.size, fill: fill)
                    let rect = bounds(points)
                    frame(points: points, rect: rect)
                    if style == .liftedTile, let crop = captureCrop(region, image: presentation.image) {
                        Image(uiImage: crop).resizable().scaledToFit()
                            .frame(width: rect.width, height: rect.height)
                            .background(.black).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.9), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 9, y: 4)
                            .scaleEffect(settled || reduced || snapshot ? 1.015 : 1)
                            .position(x: rect.midX, y: rect.midY)
                    }
                    if regions.count > 1 || style == .glassCaption || style == .numberedPins {
                        marker(index: index, rect: rect, viewport: geo.size, crowded: crowded(index, rects))
                    }
                }
                if fill && (style == .thumbnailDock || style == .captureToCard) {
                    VStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 10) {
                            ForEach(Array(regions.prefix(4).enumerated()), id: \.element.id) { index, region in
                                if let thumbnail = captureCrop(region, image: presentation.image) {
                                    VStack(spacing: 4) {
                                        Image(uiImage: thumbnail).resizable().scaledToFit()
                                            .frame(width: style == .captureToCard ? 44 : 38, height: style == .captureToCard ? 44 : 38)
                                            .padding(4).background(.white, in: RoundedRectangle(cornerRadius: 7))
                                        if regions.count > 1 { Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.white) }
                                    }
                                }
                            }
                            if style == .captureToCard {
                                Text(L10n.t("capture.captured", .preferred)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Spacer(minLength: 0)
                                Image(systemName: "checkmark.viewfinder").foregroundStyle(.white)
                            }
                        }.padding(12).background(.black.opacity(opaque ? 1 : 0.82), in: RoundedRectangle(cornerRadius: 18))
                            .offset(y: settled || reduced || snapshot ? 0 : 12)
                            .frame(maxWidth: style == .captureToCard ? 320 : nil)
                    }.padding(18).padding(.bottom, bottomInset)
                }
            }
            .opacity(settled || reduced || snapshot ? 1 : 0.2)
            .clipped()
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { withAnimation(reduced ? nil : .smooth(duration: 0.26, extraBounce: 0)) { settled = true } }
    }
    @ViewBuilder private func frame(points: [CGPoint], rect: CGRect) -> some View {
        let shifted = rect.insetBy(dx: settled || reduced || snapshot ? -5 : -9, dy: settled || reduced || snapshot ? -5 : -9)
        Group {
            switch style {
            case .perspectiveTrace:
                Quad(points: points).trim(from: 0, to: settled || reduced || snapshot ? 1 : 0.05)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .fineOutline, .softSpotlight, .frostedSurround:
                Path(roundedRect: shifted, cornerRadius: 10).stroke(.white.opacity(0.94), lineWidth: 1.5)
            case .cornerAnchors:
                Quad(points: points).stroke(.white.opacity(0.45), lineWidth: 1)
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    Circle().fill(.white).frame(width: 7, height: 7).position(p)
                }
            case .focusRails:
                Rails(rect: shifted).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .numberedPins:
                Path(roundedRect: shifted, cornerRadius: 6).stroke(.white.opacity(0.6), lineWidth: 1)
            default:
                Brackets(rect: shifted).stroke(.white, style: StrokeStyle(lineWidth: style == .glassCaption ? 2 : 3, lineCap: .round, lineJoin: .round))
            }
        }.shadow(color: .black.opacity(0.65), radius: 2, y: 1)
    }
    private func marker(index: Int, rect: CGRect, viewport: CGSize, crowded: Bool) -> some View {
        let caption = style == .glassCaption && !crowded
        let original = presentation.regions.firstIndex(where: { $0.id == presentation.shownRegions[index].id }) ?? index
        let x = min(max(caption ? rect.midX : rect.minX, caption ? 54 : 18), viewport.width - (caption ? 54 : 18))
        let y = min(max(rect.minY - 23, 18), viewport.height - 18)
        return ZStack {
            if style == .numberedPins {
                Path { path in path.move(to: CGPoint(x: x, y: y + 12)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)) }
                    .stroke(.white.opacity(0.8), lineWidth: 1)
            }
            HStack(spacing: 5) {
            Text("\(original + 1)").font(.system(.caption, design: .rounded).bold())
            if caption { Text(L10n.t("capture.code", .preferred)).font(.caption.weight(.medium)) }
        }
        .foregroundStyle(.black).padding(.horizontal, caption ? 10 : 8).frame(height: 28)
        .background(.white, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .position(x: x, y: y)
        }
    }
    private func crowded(_ index: Int, _ rects: [CGRect]) -> Bool {
        rects.enumerated().contains { $0.offset != index && $0.element.insetBy(dx: -45, dy: -28).intersects(rects[index]) }
    }
}

struct CaptureHeader: View {
    var showImage = false
    @Environment(\.bqCapture) private var capture
    @Environment(\.bqCaptureStyle) private var style
    @Environment(\.bqDesign) private var design
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var appeared = false
    var body: some View {
        if let capture, showImage && !style.usesThumbnail {
            CapturePreview(capture).frame(height: 136).clipShape(RoundedRectangle(cornerRadius: design.radius))
                .padding(.bottom, 12)
        } else if let capture, style.usesThumbnail {
            HStack(spacing: 12) {
                ForEach(Array(capture.shownRegions.prefix(4))) { region in
                    if let image = captureCrop(region, image: capture.image) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: style == .captureToCard ? 64 : 42, height: style == .captureToCard ? 64 : 42)
                            .padding(5).background(.white, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                    }
                }
                Text(L10n.t("capture.captured", .preferred)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "viewfinder").foregroundStyle(.secondary).accessibilityHidden(true)
            }.padding(12).background(design.surface, in: RoundedRectangle(cornerRadius: design.radius))
                .offset(y: appeared || reduced ? 0 : 6).opacity(appeared || reduced ? 1 : 0)
                .padding(.bottom, 12)
                .onAppear { withAnimation(reduced ? nil : .smooth(duration: 0.25)) { appeared = true } }
        }
    }
}

private func bounds(_ points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .zero }
    return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { r, p in
        CGRect(x: min(r.minX, p.x), y: min(r.minY, p.y), width: max(r.maxX, p.x) - min(r.minX, p.x), height: max(r.maxY, p.y) - min(r.minY, p.y))
    }
}
func captureCrop(_ region: CaptureRegion, image: UIImage) -> UIImage? {
    guard let cg = image.cgImage else { return nil }
    let b = region.bounds.insetBy(dx: -0.015, dy: -0.015).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !b.isNull, b.width > 0, b.height > 0 else { return nil }
    let r = CGRect(x: b.minX * CGFloat(cg.width), y: b.minY * CGFloat(cg.height), width: b.width * CGFloat(cg.width), height: b.height * CGFloat(cg.height)).integral
    return cg.cropping(to: r).map { UIImage(cgImage: $0) }
}
private struct Quad: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path { Path { p in guard let first = points.first else { return }; p.move(to: first); points.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath() } }
}
private struct Apertures: Shape {
    var rects: [CGRect]
    func path(in rect: CGRect) -> Path { Path { p in p.addRect(rect); for box in rects where box.width > 0 { p.addRoundedRect(in: box.insetBy(dx: -5, dy: -5), cornerSize: CGSize(width: 10, height: 10)) } } }
}
private struct Brackets: Shape {
    var rect: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(rect.origin.x, rect.origin.y), .init(rect.width, rect.height)) }
        set { rect = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in _: CGRect) -> Path {
        let r = rect, l = min(24, min(r.width, r.height) * 0.27)
        return Path { p in
            for (x, y, dx, dy) in [(r.minX,r.minY,1.0,1.0),(r.maxX,r.minY,-1.0,1.0),(r.maxX,r.maxY,-1.0,-1.0),(r.minX,r.maxY,1.0,-1.0)] {
                p.move(to: CGPoint(x:x, y:y+dy*l)); p.addLine(to: CGPoint(x:x,y:y)); p.addLine(to: CGPoint(x:x+dx*l,y:y))
            }
        }
    }
}
private struct Rails: Shape {
    var rect: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(rect.origin.x, rect.origin.y), .init(rect.width, rect.height)) }
        set { rect = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in _: CGRect) -> Path {
        let r = rect, l = min(24, min(r.width, r.height) * 0.2)
        return Path { p in
            for y in [r.minY, r.maxY] { p.move(to: CGPoint(x:r.midX-l,y:y)); p.addLine(to: CGPoint(x:r.midX+l,y:y)) }
            for x in [r.minX, r.maxX] { p.move(to: CGPoint(x:x,y:r.midY-l)); p.addLine(to: CGPoint(x:x,y:r.midY+l)) }
        }
    }
}
