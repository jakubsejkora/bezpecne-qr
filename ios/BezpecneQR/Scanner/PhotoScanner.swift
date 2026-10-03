import BQCore
import Foundation
import ImageIO
import Vision

/// Finds codes in a still image (photo library, share extension) with Vision.
enum PhotoScanner {
    /// Images are downsampled before decoding so huge photos can't exhaust memory.
    static let maxPixelSize = 3000

    static func codes(in data: Data, source: ScanSource = .photo) async -> [ScannedCode] {
        guard let image = downsampled(data) else { return [] }
        return await codes(in: image, source: source)
    }

    static func codes(in image: CGImage, source: ScanSource) async -> [ScannedCode] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr, .microQR, .aztec, .dataMatrix, .pdf417]
        guard let observations = try? await request.perform(on: image) else { return [] }
        var seen = Set<String>()
        var result: [ScannedCode] = []
        // Reading order: top to bottom, then left to right (Vision's origin is bottom-left).
        let sorted = observations.sorted {
            let a = $0.boundingBox.cgRect, b = $1.boundingBox.cgRect
            return abs(a.midY - b.midY) > 0.05 ? a.midY > b.midY : a.midX < b.midX
        }
        for observation in sorted {
            guard let text = observation.payloadString, !text.isEmpty, seen.insert(text).inserted else { continue }
            result.append(ScannedCode(text: text, rawBytes: observation.payloadData, symbology: symbology(observation.symbology), source: source))
        }
        return result
    }

    static func symbology(_ s: BarcodeSymbology) -> Symbology {
        switch s {
        case .microQR: return .microQR
        case .aztec: return .aztec
        case .dataMatrix: return .dataMatrix
        case .pdf417, .microPDF417: return .pdf417
        default: return .qr
        }
    }

    static func downsampled(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
