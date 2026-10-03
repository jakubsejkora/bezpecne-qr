import BQCore
import BQUI
import PhotosUI
import SwiftData
import SwiftUI

/// The main screen: full-bleed camera, "Skenovat" title, gallery button top-right,
/// Settings bottom-left and a hint at the bottom.
struct ScannerScreen: View {
    @State var flow: ScanFlow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSettings = false
    private let lang = Language.preferred

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            camera
            if let frozen = flow.frozenImage {
                Image(uiImage: frozen)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            if !flow.outline.isEmpty {
                CodeOutline(points: flow.outline)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            chrome
            if let toast = flow.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 140)
                }
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: flow.detectionCount)
        // One sheet: the chooser (several codes) turns into the result in place.
        .sheet(isPresented: Binding(get: { flow.isPresenting }, set: { if !$0 { flow.dismiss() } })) {
            Group {
                if let model = flow.result {
                    ResultScreen(model: model)
                        .presentationDetents([.large])
                } else {
                    ChooserView(candidates: flow.candidates, language: lang, onPick: { flow.choose($0) }, onClose: { flow.dismiss() })
                        .presentationDetents([.medium, .large])
                }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen(flow: flow)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await flow.scanPhoto(data)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { flow.startCamera() } else if phase == .background { flow.stopCamera() }
        }
        .onChange(of: showSettings) { _, shown in
            if shown { flow.camera.setPaused(true) } else if !flow.isPresenting { flow.camera.setPaused(false) }
        }
        .onAppear {
            flow.modelContext = modelContext
            flow.startCamera()
            #if DEBUG
            DebugLaunch.run(flow)
            if DebugLaunch.openSettings { showSettings = true }
            #endif
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: flow.toast)
    }

    @ViewBuilder
    private var camera: some View {
        switch flow.cameraAuthorization {
        case .authorized:
            if flow.cameraUnavailable {
                CameraUnavailableView(pickerItem: $pickerItem)
            } else {
                CameraPreview(session: flow.camera.session, box: flow.preview)
                    .ignoresSafeArea()
            }
        case .notDetermined:
            Color.black.ignoresSafeArea()
        case .denied:
            CameraDeniedView(pickerItem: $pickerItem)
        }
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(L10n.t("scan.title", [:], lang))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 8)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .appGlass(in: Circle())
                }
                .accessibilityLabel(L10n.t("scan.gallery", [:], lang))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            if flow.cameraAuthorization != .denied {
                Button {
                    showSettings = true
                } label: {
                    Label(L10n.t("scan.settings", [:], lang), systemImage: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .appGlass()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                VStack(spacing: 2) {
                    Text(L10n.t("scan.hint", [:], lang))
                        .font(.headline)
                    Text(L10n.t("scan.hintSub", [:], lang))
                        .font(.subheadline)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .appGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    showSettings = true
                } label: {
                    Label(L10n.t("scan.settings", [:], lang), systemImage: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .appGlass()
                }
                .padding(20)
            }
        }
    }
}

/// The outline drawn around the detected code.
struct CodeOutline: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

/// Shown when no camera can be started (for example in the Simulator): offer the gallery.
struct CameraUnavailableView: View {
    @Binding var pickerItem: PhotosPickerItem?
    private let lang = Language.preferred

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48, weight: .semibold))
                .accessibilityHidden(true)
            Text(L10n.t("error.camera", [:], lang))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            PhotosPicker(L10n.t("denied.gallery", [:], lang), selection: $pickerItem, matching: .images)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

/// Shown when camera access is off: explain, link to Settings, offer the gallery.
struct CameraDeniedView: View {
    @Binding var pickerItem: PhotosPickerItem?
    @Environment(\.openURL) private var openURL
    private let lang = Language.preferred

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48, weight: .semibold))
                .accessibilityHidden(true)
            Text(L10n.t("denied.title", [:], lang))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(L10n.t("denied.text", [:], lang))
                .multilineTextAlignment(.center)
                .opacity(0.85)
            Button(L10n.t("denied.settings", [:], lang)) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            PhotosPicker(L10n.t("denied.gallery", [:], lang), selection: $pickerItem, matching: .images)
                .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, material fallback on iOS 18.
    @ViewBuilder
    nonisolated func appGlass(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
