import BQCore
import BQUI
import PhotosUI
import SwiftUI

struct ScannerScreen: View {
    @State var flow: ScanFlow
    @State private var picking = false
    @State private var photoTask: Task<Void, Never>?
    @State private var photoGeneration = UUID()
    @Environment(\.bqDesign) private var design
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.bqAimGuideStyle) private var aimStyle
    @Environment(\.bqSignalPreset) private var signalPreset
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let capture = flow.capture {
                CapturePreview(capture, fill: true, bottomInset: flow.replayHeld ? 110 : 28).ignoresSafeArea()
            } else if flow.cameraAuthorization == .authorized && !flow.cameraUnavailable {
                CameraPreview(session: flow.camera.session, box: flow.preview).ignoresSafeArea()
            }
            #if DEBUG || DESIGN_REVIEW
            if flow.isAimPreview {
                GeometryReader { geo in
                    if let scene = UserDefaults.standard.string(forKey: "BQCameraScene"), ["bright", "dark"].contains(scene) {
                        (scene == "bright" ? Color.white : Color.black)
                    } else {
                        Image(uiImage: CaptureExamples.make(.single).image).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                    }
                }.ignoresSafeArea()
            }
            #endif
            if !flow.isAimPreview && flow.capture == nil && (flow.cameraAuthorization == .denied || flow.cameraUnavailable) {
                unavailable
            } else if flow.capture == nil {
                GeometryReader { viewport in
                    AimGuide().frame(width: min(260, viewport.size.width - 40), height: min(260, viewport.size.width - 40))
                        .position(x: viewport.size.width / 2, y: viewport.size.height / 2)
                }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                header.measureFadeHeader()
                Spacer(minLength: 16)
                if flow.cameraState == .starting || flow.cameraState == .interrupted {
                    Label(L10n.t(flow.cameraState == .starting ? "scan.starting" : "scan.interrupted", .preferred), systemImage: "camera")
                        .font(.subheadline).foregroundStyle(.white).padding(12)
                        .background(.black.opacity(0.8), in: Capsule()).padding(.bottom, 12)
                }
                if flow.replayHeld {
                    #if DEBUG || DESIGN_REVIEW
                    HStack {
                        Button(L10n.t("lab.replayShort", .preferred)) { CaptureExamples.replay(flow, scene: CaptureExamples.Scene(rawValue: flow.replayScene) ?? .single) }
                        Spacer()
                        Button(L10n.t("lab.resultShort", .preferred)) { flow.continueReplay() }
                        Spacer()
                        Button(L10n.t("act.close", .preferred)) { flow.dismiss() }
                    }.font(.subheadline.bold()).padding(16).background(.regularMaterial, in: Capsule()).padding(.bottom, 14)
                    #endif
                }
                if let toast = flow.toast {
                    Text(toast).font(.callout).padding(14).background(.regularMaterial, in: Capsule()).padding(.bottom, 12)
                }
            }.padding(.horizontal, design.padding).scannerFadeBackground()
        }
        .sheet(isPresented: $picking, onDismiss: {
            flow.photoPickerVisible = false; flow.updateCamera()
        }) {
            NativeImagePicker { provider in
                if let provider { importPhoto(provider) }
                picking = false
            }.ignoresSafeArea()
        }
        .onChange(of: picking) { _, value in
            if value { flow.photoPickerVisible = true; flow.updateCamera() }
        }
        .onDisappear { photoGeneration = UUID(); photoTask?.cancel(); flow.cancelImport() }
        .onChange(of: flow.appActive) { _, active in
            if !active { photoGeneration = UUID(); photoTask?.cancel(); flow.cancelImport() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: flow.detectionCount)
        #if DEBUG || DESIGN_REVIEW
        .task(id: flow.isAimPreview && flow.scannerVisible && flow.appActive) {
            await DebugLaunch.recordAimComparison(flow)
        }
        #endif
    }
    private func importPhoto(_ provider: NSItemProvider) {
        photoTask?.cancel(); let ticket = UUID(); photoGeneration = ticket
        flow.importing = true; flow.updateCamera()
        photoTask = Task {
            do {
                let data = try await ProviderImage.load(provider)
                guard !Task.isCancelled, photoGeneration == ticket else { return }
                await flow.scanPhoto(data)
            } catch {
                guard photoGeneration == ticket else { return }
                flow.cancelImport()
                if !Task.isCancelled { flow.show(toast: L10n.t("share.imageError", .preferred)) }
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) { brand; Spacer(minLength: 6); cameraButtons }
                VStack(alignment: .leading, spacing: 8) { brand; cameraButtons }
            }
            Text(L10n.t("scan.rcSubtitle", .preferred)).font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(design.accentInk).padding(.top, 10)
    }
    private var brand: some View {
        Text("Bezpečné QR").font(.system(.title2, weight: .bold)).tracking(-0.5)
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    private var cameraButtons: some View {
        HStack(spacing: 8) {
            if flow.torchAvailable {
                Button(action: flow.toggleTorch) {
                    Image(systemName: flow.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.body.weight(.semibold)).frame(width: 44, height: 44)
                        .foregroundStyle(flow.torchOn ? .black : .white)
                        .background(flow.torchOn ? .white : .black, in: Circle())
                }.accessibilityLabel(L10n.t(flow.torchOn ? "scan.torchOff" : "scan.torchOn", .preferred))
            }
            Button { if flow.isAimPreview { flow.dismiss() }; picking = true } label: {
                Label(L10n.t("scan.galleryShort", .preferred), systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(.black, in: Capsule())
            }.accessibilityLabel(L10n.t("scan.gallery", .preferred)).accessibilityIdentifier("scan.photos")
        }
    }
    private var unavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: flow.cameraAuthorization == .denied ? "camera.fill" : "photo.on.rectangle.angled")
                .font(.system(size: 38, weight: .light)).accessibilityHidden(true)
            Text(L10n.t(flow.cameraAuthorization == .denied ? "denied.title" : "error.camera", .preferred)).font(.title3.bold()).multilineTextAlignment(.center)
            Button(L10n.t("denied.gallery", .preferred)) { picking = true }
                .padding(.vertical, 13).padding(.horizontal, 22).background(.white, in: Capsule()).foregroundStyle(.black)
            if flow.cameraUnavailable && flow.cameraAuthorization == .authorized {
                Button(L10n.t("scan.retryCamera", .preferred), action: flow.retryCamera)
                    .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
            }
            if flow.cameraAuthorization == .denied {
                Link(L10n.t("denied.settings", .preferred), destination: URL(string: UIApplication.openSettingsURLString)!).font(.subheadline).frame(minHeight: 44)
            }
        }.foregroundStyle(.white).padding(22)
    }
}
