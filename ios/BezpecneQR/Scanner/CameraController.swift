import AVFoundation
import BQCore
import CoreImage
import UIKit

/// One code the camera sees, in normalized metadata-output coordinates.
struct DetectedCode: Sendable, Equatable {
    var text: String
    var symbology: Symbology
    var bounds: CGRect
    var corners: [CGPoint]
}

/// Owns the capture session. Session configuration, start and stop are serialized on a private
/// queue (off the main actor); detections are delivered to the main actor.
final class CameraController: NSObject, @unchecked Sendable {
    enum Authorization: Sendable { case authorized, notDetermined, denied }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cz.bezpecneqr.camera.session")
    private let outputQueue = DispatchQueue(label: "cz.bezpecneqr.camera.output")
    private let metadataOutput = AVCaptureMetadataOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()

    private let lock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var paused = false
    private var configured = false

    /// Called on the main actor whenever codes are in view (not while paused).
    @MainActor var onDetect: (([DetectedCode]) -> Void)?
    /// Called on the main actor when no camera can be configured (e.g. the Simulator).
    @MainActor var onUnavailable: (() -> Void)?

    static let symbologies: [AVMetadataObject.ObjectType: Symbology] = [
        .qr: .qr, .microQR: .microQR, .aztec: .aztec, .dataMatrix: .dataMatrix, .pdf417: .pdf417,
    ]

    static var authorization: Authorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: Lifecycle

    func start() {
        sessionQueue.async { [self] in
            if !configured { configure() }
            guard configured else {
                Task { @MainActor [weak self] in self?.onUnavailable?() }
                return
            }
            // Pausing is owned by the scan flow (sheets, settings); starting never unpauses.
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Stops delivering detections (the result sheet is open) without tearing the session down.
    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }

    private var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    // MARK: Configuration

    private func configure() {
        guard let device = CameraController.bestDevice(),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        guard session.canAddInput(input), session.canAddOutput(metadataOutput), session.canAddOutput(videoOutput) else { return }
        session.addInput(input)
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: outputQueue)
        metadataOutput.metadataObjectTypes = CameraController.symbologies.keys.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        tuneFocus(device)
        configured = true
    }

    /// Prefer a virtual multi-camera device, which switches to the ultra-wide lens for close-up
    /// (macro) focus on newer iPhones; fall back to the wide camera.
    static func bestDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .back)
        return discovery.devices.first
    }

    private func tuneFocus(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isVirtualDevice, let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                // Start at the wide-lens field of view; the system switches lenses for close focus.
                device.videoZoomFactor = CGFloat(truncating: wide)
            } else {
                // Zoom in just enough that a 20 mm code filling ~half the frame is in focus range.
                let minFocus = Float(device.minimumFocusDistance) // mm, -1 when unknown
                if minFocus > 0 {
                    let fov = device.activeFormat.videoFieldOfView * .pi / 180
                    let subjectDistance = (20 / 0.5) / tan(fov / 2)
                    if subjectDistance < minFocus {
                        device.videoZoomFactor = min(CGFloat(minFocus / subjectDistance), device.activeFormat.videoMaxZoomFactor)
                    }
                }
            }
        } catch {
            // Focus tuning is optional.
        }
    }

    // MARK: Frozen frame

    /// The latest camera frame as an upright image (used to freeze the preview).
    func snapshot() -> UIImage? {
        lock.lock()
        let buffer = latestFrame
        lock.unlock()
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

extension CameraController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !isPaused else { return }
        let codes: [DetectedCode] = objects.compactMap { object in
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  let text = code.stringValue, !text.isEmpty,
                  let symbology = CameraController.symbologies[code.type] else { return nil }
            return DetectedCode(text: text, symbology: symbology, bounds: code.bounds, corners: code.corners)
        }
        guard !codes.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.onDetect?(codes)
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isPaused, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latestFrame = buffer
        lock.unlock()
    }
}
