import BQCore
import BQUI
import SwiftUI

/// Native sheet/cover transitions retain the scan session. Only a user dismissal closes it.
@MainActor @Observable
final class ResultPresentationCoordinator {
    enum Surface: Equatable {
        case chooser, standard, sheet, popup, fullPage
        var isSheet: Bool { self == .chooser || self == .standard || self == .sheet }
    }
    private(set) var presented: Surface?
    private(set) var pending: Surface?
    private(set) var transitioning = false
    var sheetVisible: Bool { presented?.isSheet == true && !transitioning }
    var coverVisible: Bool { presented?.isSheet == false && !transitioning }

    func update(_ desired: Surface?) {
        if transitioning { pending = desired; return }
        guard presented != desired else { return }
        if presented == nil { presented = desired; return }
        if let desired, desired.isSheet == presented?.isSheet { presented = desired; return }
        pending = desired; transitioning = true
    }
    func didDismiss() {
        presented = pending; pending = nil; transitioning = false
    }
}

struct ScanResultPresentation: ViewModifier {
    let flow: ScanFlow
    @Binding var recovery: Bool
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var coordinator = ResultPresentationCoordinator()
    @State private var contentHeight: CGFloat = 520
    @State private var availableHeight: CGFloat = 800
    @State private var detent = PresentationDetent.height(520)
    private var desired: ResultPresentationCoordinator.Surface? {
        !flow.photoPickerVisible && flow.isPresenting ? (flow.result == nil ? .chooser : .sheet) : nil
    }
    private var fitHeight: CGFloat { min(max(contentHeight, 360), max(360, availableHeight * 0.92)) }
    private var detents: Set<PresentationDetent> {
        textSize.isAccessibilitySize ? [.large] : coordinator.presented == .chooser ? [.large] : [.height(fitHeight), .large]
    }
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { availableHeight = $0 }
            .sheet(isPresented: Binding(get: { coordinator.sheetVisible }, set: { value in
                if !value && !coordinator.transitioning { flow.dismiss(); coordinator.update(nil) }
            }), onDismiss: {
                coordinator.didDismiss(); flow.presentationDidDismiss()
            }) {
                AppearanceHost {
                    Group {
                        if let model = flow.result {
                            ResultScreen(model: model, onHeightChange: resize)
                        } else {
                            ChooserView(candidates: flow.candidates, checking: flow.comparison?.checking ?? [],
                                        language: .preferred, onPick: flow.choose, onClose: flow.dismiss)
                        }
                    }.environment(\.bqCapture, flow.capture)
                        .onAppear { flow.presentationVisible = true; flow.updateCamera() }
                        .sheet(isPresented: $recovery) {
                            AppearanceHost {
                                NavigationStack {
                                    RecoveryGuideScreen().toolbar { Button(L10n.t("act.close", .preferred)) { recovery = false } }
                                }
                            }
                        }
                }
                .presentationDetents(detents, selection: $detent)
                .presentationDragIndicator(.visible)
            }
            .onChange(of: desired, initial: true) { _, value in
                if textSize.isAccessibilitySize { detent = .large }
                else if value == .chooser { detent = .large }
                else if coordinator.presented == nil || coordinator.presented == .chooser { detent = .height(fitHeight) }
                coordinator.update(value)
            }
            .onChange(of: textSize) { _, value in if value.isAccessibilitySize { detent = .large } }
    }
    private func resize(_ height: CGFloat) {
        guard abs(contentHeight - height) > 2 else { return }
        let fitted = detent != .large && detent != .medium
        contentHeight = height
        if fitted && !textSize.isAccessibilitySize { detent = .height(fitHeight) }
    }
}
