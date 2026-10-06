import BQServices
import Foundation
import UniformTypeIdentifiers
import UIKit

/// Read while the provider's URL is valid, with a hard bound; cancel the provider on dismissal.
final class ProviderImage: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var progress: Progress?
    private var cancelled = false
    @MainActor static func load(_ provider: NSItemProvider) async throws -> Data {
        let request = ProviderImage()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in request.start(provider, continuation) }
        } onCancel: { request.cancel() }
    }
    private func start(_ provider: NSItemProvider, _ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation; lock.unlock()
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
        let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { [self] url, error in
            do {
                guard let url else { throw error ?? ImageScanError.unreadable }
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                let data = try file.read(upToCount: ImageCodeScanner.maxBytes + 1) ?? Data()
                guard data.count <= ImageCodeScanner.maxBytes else { throw ImageScanError.tooLarge }
                finish(.success(data))
            } catch { finish(.failure(error)) }
        }
        lock.lock(); self.progress = progress; let stop = cancelled; lock.unlock()
        if stop { progress.cancel() }
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: result)
    }
    private func cancel() {
        lock.lock(); cancelled = true; let p = progress; lock.unlock()
        p?.cancel(); finish(.failure(CancellationError()))
    }
}
