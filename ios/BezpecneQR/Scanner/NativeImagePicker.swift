import PhotosUI
import SwiftUI

/// The native image picker is hosted by a sheet whose actual dismissal gates camera restart.
struct NativeImagePicker: UIViewControllerRepresentable {
    let onPick: (NSItemProvider?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images; configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (NSItemProvider?) -> Void
        init(onPick: @escaping (NSItemProvider?) -> Void) { self.onPick = onPick }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results.first?.itemProvider)
        }
    }
}
