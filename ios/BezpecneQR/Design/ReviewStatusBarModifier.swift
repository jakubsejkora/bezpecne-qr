import BQUI
import SwiftUI

/// Scoped to app-owned scanning/results. Native pickers and the other tabs keep normal chrome.
struct ReviewStatusBarModifier: ViewModifier {
    let active: Bool
    @Environment(\.bqReviewStatusBar) private var preference
    func body(content: Content) -> some View {
        #if DEBUG || DESIGN_REVIEW
        let hidden = active && preference == .immersive
        if #available(iOS 27, *) {
            content.toolbarVisibility(hidden ? .hidden : .visible, for: .statusBar)
        } else {
            content.statusBarHidden(hidden)
        }
        #else
        content
        #endif
    }
}
