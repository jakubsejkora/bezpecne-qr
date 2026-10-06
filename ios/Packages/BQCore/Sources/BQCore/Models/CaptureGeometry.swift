import Foundation
import CoreGraphics

/// Presentation geometry only; never used to compute risk. Coordinates are normalized, upright,
/// top-left origin, so camera and imported images share exactly the same rendering path.
public struct CaptureRegion: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var corners: [CGPoint]
    public init(id: UUID = UUID(), corners: [CGPoint]) { self.id = id; self.corners = corners }
    public init(id: UUID = UUID(), rect: CGRect) {
        self.init(id: id, corners: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
    }
    public var bounds: CGRect {
        guard !corners.isEmpty, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return .zero }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    public func points(in viewport: CGSize, image: CGSize, fill: Bool) -> [CGPoint] {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return [] }
        let sx = viewport.width / image.width, sy = viewport.height / image.height
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let w = image.width * scale, h = image.height * scale
        return corners.map { CGPoint(x: (viewport.width - w) / 2 + $0.x * w, y: (viewport.height - h) / 2 + $0.y * h) }
    }
}

public struct LocatedCode: Sendable, Identifiable {
    public var code: ScannedCode
    public var region: CaptureRegion
    public var id: UUID { region.id }
    public init(code: ScannedCode, region: CaptureRegion) { self.code = code; self.region = region }
}
