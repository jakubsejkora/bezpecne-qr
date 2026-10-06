import AVFoundation
import Foundation
import Testing
@testable import BezpecneQR

private final class TestCaptureSession: AVCaptureSession, @unchecked Sendable {
    private let stateLock = NSLock()
    private var testRunning = false
    private var starts = 0
    var startCount: Int { stateLock.withLock { starts } }
    override var isRunning: Bool { stateLock.withLock { testRunning } }
    override func startRunning() { stateLock.withLock { testRunning = true; starts += 1 } }
    override func stopRunning() { stateLock.withLock { testRunning = false } }
}

@MainActor @Suite(.serialized) struct CameraRecoveryTests {
    @Test func noFramesTriggersOnlyOneAutomaticRestartThenExplicitRetry() async throws {
        let session = TestCaptureSession()
        let camera = CameraController(session: session, preconfigured: true, startupTimeout: 0.04)
        var states: [CameraController.State] = []
        camera.onState = { states.append($0) }
        camera.start()
        for _ in 0..<20 { camera.start() } // Reconciliation never creates parallel starts/watchdogs.
        try await Task.sleep(for: .milliseconds(170))
        #expect(session.startCount == 2)
        #expect(states.last == .failed)
        camera.retry()
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.startCount == 3)
        camera.stop()
        try await Task.sleep(for: .milliseconds(120))
        #expect(session.startCount == 3 && !session.isRunning)
        #expect(states.last == .stopped)
    }
    @Test func interruptionAndResetRespectLatestVisibility() async throws {
        let session = TestCaptureSession()
        let camera = CameraController(session: session, preconfigured: true, startupTimeout: 1)
        var states: [CameraController.State] = []
        camera.onState = { states.append($0) }
        camera.start(); try await Task.sleep(for: .milliseconds(30))
        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: session)
        try await Task.sleep(for: .milliseconds(30))
        #expect(states.last == .interrupted)
        camera.stop()
        NotificationCenter.default.post(name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: session,
            userInfo: [AVCaptureSessionErrorKey: NSError(domain: AVFoundationErrorDomain, code: AVError.mediaServicesWereReset.rawValue)])
        try await Task.sleep(for: .milliseconds(80))
        #expect(!session.isRunning && states.last == .stopped)
        camera.start(); try await Task.sleep(for: .milliseconds(30))
        #expect(session.isRunning && states.last == .starting)
        camera.stop()
    }
}
