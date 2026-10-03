import BQCore
import BQUI
import SwiftData
import SwiftUI

@main
struct BezpecneQRApp: App {
    private let container = HistoryStore.makeContainer()
    @State private var flow = ScanFlow(checker: LinkChecker())
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboardingDone {
                    ScannerScreen(flow: flow)
                } else {
                    OnboardingScreen { onboardingDone = true }
                }
            }
            .preferredColorScheme(nil)
        }
        .modelContainer(container)
    }
}

/// Two short pages: what the app does (and what it checks over the internet), then the camera.
struct OnboardingScreen: View {
    let done: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let lang = Language.preferred

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.55, blue: 1.0), Color(red: 0.12, green: 0.23, blue: 0.54)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 20)
                Image(systemName: page == 0 ? "checkmark.shield.fill" : "camera.viewfinder")
                    .font(.system(size: 64, weight: .semibold))
                    .symbolEffect(.bounce, value: page)
                    .frame(width: 112, height: 112)
                    .appGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .accessibilityHidden(true)
                if page == 0 {
                    Text(L10n.t("onb.1.title", [:], lang)).font(.largeTitle.bold())
                    Text(L10n.t("onb.1.text", [:], lang)).font(.title3)
                    VStack(alignment: .leading, spacing: 12) {
                        bullet("iphone", "onb.1.b1")
                        bullet("lock.fill", "onb.1.b2")
                        bullet("banknote.fill", "onb.1.b3")
                    }
                    .padding(.top, 6)
                    Text(L10n.t("onb.privacyNote", [:], lang))
                        .font(.footnote)
                        .opacity(0.85)
                        .padding(.top, 6)
                } else {
                    Text(L10n.t("onb.2.title", [:], lang)).font(.largeTitle.bold())
                    Text(L10n.t("onb.2.text", [:], lang)).font(.title3)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == page ? 1 : 0.4)).frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                if page == 0 {
                    primary(L10n.t("onb.continue", [:], lang)) {
                        withAnimation(reduceMotion ? nil : .easeInOut) { page = 1 }
                    }
                    Button(L10n.t("onb.skip", [:], lang)) { done() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    primary(L10n.t("onb.allowCamera", [:], lang)) {
                        Task {
                            _ = await CameraController.requestAccess()
                            done()
                        }
                    }
                    Button(L10n.t("onb.notNow", [:], lang)) { done() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .foregroundStyle(.white)
            .padding(28)
        }
    }

    private func bullet(_ icon: String, _ key: String) -> some View {
        Label {
            Text(L10n.t(key, [:], lang)).font(.body.weight(.medium))
        } icon: {
            Image(systemName: icon).frame(width: 28)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Color(red: 0.12, green: 0.23, blue: 0.54))
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
