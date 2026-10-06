import AVFoundation
import BQCore
import SwiftUI

/// Hosts the live camera preview and converts metadata coordinates into view coordinates.
@MainActor
final class PreviewBox {
    fileprivate weak var layer: AVCaptureVideoPreviewLayer?

    func region(of code: DetectedCode, imageSize: CGSize) -> CaptureRegion {
        guard let layer, imageSize.width > 0, imageSize.height > 0 else { return CaptureRegion(corners: []) }
        let size = layer.bounds.size
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        guard scale > 0 else { return CaptureRegion(corners: []) }
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CaptureRegion(corners: viewCorners(of: code).map {
            CGPoint(x: ($0.x - (size.width - w) / 2) / w, y: ($0.y - (size.height - h) / 2) / h)
        })
    }

    /// Converts a code's normalized corners to points in the preview view.
    func viewCorners(of code: DetectedCode) -> [CGPoint] {
        guard let layer else { return [] }
        if !code.corners.isEmpty {
            return code.corners.map { layer.layerPointConverted(fromCaptureDevicePoint: $0) }
        }
        let r = layer.layerRectConverted(fromMetadataOutputRect: code.bounds)
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let box: PreviewBox

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        box.layer = view.previewLayer
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        box.layer = view.previewLayer
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90), connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }
}
