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
    enum State: String, Sendable { case stopped, starting, running, interrupted, failed }

    let session: AVCaptureSession
    private let startupTimeout: TimeInterval
    private let sessionQueue = DispatchQueue(label: "cz.bezpecneqr.camera.session")
    private let outputQueue = DispatchQueue(label: "cz.bezpecneqr.camera.output")
    private let metadataOutput = AVCaptureMetadataOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()

    private let lock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var paused = false
    private var configured = false
    // Desired state and frame generation cross queues under this lock. Session state stays on sessionQueue.
    private var desiredRunning = false
    private var generation = 0
    private var frameGeneration = -1
    private var interrupted = false
    private var restartAttempted = false
    private var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []
    @MainActor var onState: ((State) -> Void)?
    @MainActor var onTorch: ((Bool, Bool) -> Void)?

    init(session: AVCaptureSession = AVCaptureSession(), preconfigured: Bool = false, startupTimeout: TimeInterval = 3) {
        self.session = session; self.configured = preconfigured; self.startupTimeout = startupTimeout
        super.init()
        let center = NotificationCenter.default
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] notification in
                let reset = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
                self?.sessionQueue.async { [weak self] in self?.handle(name, mediaReset: reset) }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

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

    func start() { request(running: true) }
    func stop() { request(running: false) }
    func retry() { request(running: true, force: true) }

    private func request(running: Bool, force: Bool = false) {
        lock.lock()
        let changed = desiredRunning != running || force
        if changed { desiredRunning = running; generation += 1; frameGeneration = -1 }
        let ticket = generation
        lock.unlock()
        guard changed else { return }
        sessionQueue.async { [self] in
            guard currentTicket == ticket else { return }
            restartAttempted = false
            if force && session.isRunning { session.stopRunning() }
            reconcile(ticket)
        }
    }
    private var currentTicket: Int { lock.lock(); defer { lock.unlock() }; return generation }
    private var wantsRunning: Bool { lock.lock(); defer { lock.unlock() }; return desiredRunning }
    private func reconcile(_ ticket: Int) {
        guard ticket == currentTicket else { return }
        guard wantsRunning else {
            torch(false); if session.isRunning { session.stopRunning() }
            discardFrame(); publish(.stopped, ticket); return
        }
        guard !interrupted else { torch(false); publish(.interrupted, ticket); return }
        if !configured { configure() }
        guard configured else { publish(.failed, ticket); return }
        publish(.starting, ticket)
        if !session.isRunning { session.startRunning() }
        guard currentTicket == ticket, wantsRunning else {
            torch(false); if session.isRunning { session.stopRunning() }; return
        }
        sessionQueue.asyncAfter(deadline: .now() + startupTimeout) { [weak self] in self?.verifyFrames(ticket) }
    }
    private func verifyFrames(_ ticket: Int) {
        guard currentTicket == ticket, wantsRunning, !interrupted else { return }
        lock.lock(); let seen = frameGeneration == ticket; lock.unlock()
        guard !seen else { return }
        torch(false)
        if session.isRunning { session.stopRunning() }
        if !restartAttempted {
            restartAttempted = true; reconcile(ticket)
        } else { publish(.failed, ticket) }
    }
    private func publish(_ state: State, _ ticket: Int) {
        Task { @MainActor [weak self] in
            guard let self, self.currentTicket == ticket else { return }
            self.onState?(state)
            if state == .failed { self.onUnavailable?() }
        }
    }
    private func handle(_ name: Notification.Name, mediaReset: Bool) {
        torch(false)
        if name == AVCaptureSession.wasInterruptedNotification {
            interrupted = true; publish(.interrupted, currentTicket)
        } else {
            interrupted = false
            lock.lock(); frameGeneration = -1; lock.unlock()
            if name == AVCaptureSession.runtimeErrorNotification && !mediaReset {
                publish(.failed, currentTicket)
            } else { reconcile(currentTicket) }
        }
    }
    func setTorch(_ enabled: Bool) {
        sessionQueue.async { [self] in torch(enabled && wantsRunning && !isPaused && !interrupted) }
    }
    private func torch(_ enabled: Bool) {
        guard let device, device.hasTorch else {
            Task { @MainActor [weak self] in self?.onTorch?(false, false) }; return
        }
        do {
            try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
            device.torchMode = enabled && device.isTorchAvailable ? .on : .off
        } catch { }
        let on = device.torchMode == .on, available = device.isTorchAvailable
        Task { @MainActor [weak self] in self?.onTorch?(on, available) }
    }

    /// Stops delivering detections (the result sheet is open) without tearing the session down.
    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
        if value { setTorch(false) }
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
        self.device = device
        tuneFocus(device)
        configured = true
        torch(false)
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

    func discardFrame() {
        lock.lock(); latestFrame = nil; lock.unlock()
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
        let ticket = currentTicket
        Task { @MainActor [weak self] in
            guard let self, self.currentTicket == ticket, self.wantsRunning, !self.isPaused else { return }
            self.onDetect?(codes)
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        let ticket = generation
        let first = desiredRunning && !paused && frameGeneration != ticket
        if !paused { latestFrame = buffer }
        if first { frameGeneration = ticket }
        lock.unlock()
        if first { sessionQueue.async { [weak self] in self?.publish(.running, ticket) } }
    }
}
