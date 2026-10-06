import BQCore
import Foundation
import ImageIO
import Vision

public struct ScannedImage: Sendable {
    public let image: CGImage
    public let codes: [LocatedCode]
}

public enum ImageScanError: Error { case tooLarge, unreadable }

/// Shared by Photos and the extension. Decode one bounded, upright thumbnail; never retain the original.
public enum ImageCodeScanner {
    public static let maxBytes = 30 * 1024 * 1024
    public static let maxPixels = 100_000_000
    public static let maxPixelSize = 3000

    public static func scan(_ data: Data, source: ScanSource = .photo) async throws -> ScannedImage {
        guard data.count <= maxBytes else { throw ImageScanError.tooLarge }
        guard let sourceImage = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImageScanError.unreadable }
        guard width <= maxPixels / height else { throw ImageScanError.tooLarge }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize]
        guard let image = CGImageSourceCreateThumbnailAtIndex(sourceImage, 0, options as CFDictionary) else { throw ImageScanError.unreadable }
        return ScannedImage(image: image, codes: try await codes(in: image, source: source))
    }

    public static func codes(in image: CGImage, source: ScanSource) async throws -> [LocatedCode] {
        try Task.checkCancellation()
        #if targetEnvironment(simulator)
        // Revision 4's detector model is unavailable in the iOS 27 simulator runtime.
        // Device builds keep the existing modern Vision engine; simulator QA uses Apple's CPU revision.
        return try simulatorCodes(in: image, source: source)
        #else
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr, .microQR, .aztec, .dataMatrix, .pdf417]
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        let sorted = observations.sorted {
            let a = $0.boundingBox.cgRect, b = $1.boundingBox.cgRect
            return abs(a.midY - b.midY) > 0.05 ? a.midY > b.midY : a.midX < b.midX
        }
        return sorted.compactMap { o in
            guard let text = o.payloadString, !text.isEmpty else { return nil }
            let points = [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
            let sym: Symbology
            switch o.symbology {
            case .microQR: sym = .microQR
            case .aztec: sym = .aztec
            case .dataMatrix: sym = .dataMatrix
            case .pdf417, .microPDF417: sym = .pdf417
            default: sym = .qr
            }
            return LocatedCode(code: ScannedCode(text: text, rawBytes: o.payloadData, symbology: sym, source: source),
                               region: CaptureRegion(corners: points))
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private static func simulatorCodes(in image: CGImage, source: ScanSource) throws -> [LocatedCode] {
        let request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision1
        request.usesCPUOnly = true
        let supported = try request.supportedSymbologies()
        request.symbologies = [VNBarcodeSymbology.qr, .microQR, .aztec, .dataMatrix, .pdf417].filter { supported.contains($0) }
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.05 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.midX < $1.boundingBox.midX
        }.compactMap { o in
            guard let text = o.payloadStringValue, !text.isEmpty else { return nil }
            let sym: Symbology = switch o.symbology { case .microQR: .microQR; case .aztec: .aztec; case .dataMatrix: .dataMatrix; case .pdf417: .pdf417; default: .qr }
            return LocatedCode(code: ScannedCode(text: text, symbology: sym, source: source), region: CaptureRegion(corners:
                [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }))
        }
    }
    #endif
}
