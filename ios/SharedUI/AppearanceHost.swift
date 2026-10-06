import BQCore
import BQServices
import BQUI
import SwiftUI

/// Product appearance is explicit; only the two remaining internal comparisons read preferences.
struct AppearanceHost<Content: View>: View {
    var hidesStatusBar = true
    @AppStorage(SharedSettings.capture, store: SharedSettings.defaults) private var capture = "cameraCorners"
    @AppStorage(SharedSettings.scoreChart, store: SharedSettings.defaults) private var chart = "spectrum"
    @ViewBuilder var content: Content
    private var style: CaptureStyle {
        #if DEBUG || DESIGN_REVIEW
        CaptureStyle(rawValue: capture) ?? .cameraCorners
        #else
        .cameraCorners
        #endif
    }
    private var scoreChart: ScoreChartStyle {
        #if DEBUG || DESIGN_REVIEW
        ScoreChartStyle(rawValue: chart) ?? .spectrum
        #else
        .spectrum
        #endif
    }
    var body: some View {
        content.environment(\.bqDesign, .signal).environment(\.bqCaptureStyle, style)
            .environment(\.bqAimGuideStyle, .roundedCorners)
            .environment(\.bqSignalPreset, .fade).environment(\.bqResultPresentation, .sheet)
            .environment(\.bqScoreChart, scoreChart).environment(\.bqFadeTreatment, .vivid)
            .environment(\.bqReviewStatusBar, .immersive).environment(\.bqReviewControls, nil)
            .tint(.primary).modifier(AppStatusBarModifier(hidden: hidesStatusBar))
    }
}

struct AppStatusBarModifier: ViewModifier {
    var hidden = true
    @ViewBuilder func body(content: Content) -> some View {
        if hidden {
            if #available(iOS 27, *) { content.toolbarVisibility(.hidden, for: .statusBar) }
            else { content.statusBarHidden(true) }
        } else { content }
    }
}
