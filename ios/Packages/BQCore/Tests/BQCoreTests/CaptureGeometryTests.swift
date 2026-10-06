import CoreGraphics
import Foundation
import Testing
@testable import BQCore

struct CaptureGeometryTests {
    @Test func fitAndFillUseTheSameUprightCoordinates() {
        let region = CaptureRegion(rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let fit = region.points(in: CGSize(width: 400, height: 400), image: CGSize(width: 200, height: 400), fill: false)
        #expect(fit == [CGPoint(x: 150, y: 100), CGPoint(x: 250, y: 100), CGPoint(x: 250, y: 300), CGPoint(x: 150, y: 300)])
        let fill = region.points(in: CGSize(width: 400, height: 400), image: CGSize(width: 200, height: 400), fill: true)
        #expect(fill == [CGPoint(x: 100, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 400), CGPoint(x: 100, y: 400)])
    }
    @Test func tiltedCornersAndIdentitySurviveProjection() {
        let id = UUID()
        let corners = [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.6, y: 0.2), CGPoint(x: 0.7, y: 0.6), CGPoint(x: 0.3, y: 0.7)]
        let region = CaptureRegion(id: id, corners: corners)
        let located = LocatedCode(code: ScannedCode(text: "https://example.org"), region: region)
        #expect(located.id == id)
        #expect(region.points(in: CGSize(width: 100, height: 100), image: CGSize(width: 100, height: 100), fill: true) == corners.map { CGPoint(x: $0.x * 100, y: $0.y * 100) })
        #expect(abs(region.bounds.width - 0.5) < 0.0001)
        #expect(region.points(in: .zero, image: .zero, fill: true).isEmpty)
    }
}
