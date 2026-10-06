import BQCore
import BQServices
import BQUI
import SwiftData
import SwiftUI

@main
struct BezpecneQRApp: App {
    private let container: ModelContainer
    @State private var flow = ScanFlow(checker: LinkChecker())
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false
    init() {
        SharedSettings.migrate(); container = HistoryStore.makeContainer()
        #if DEBUG || DESIGN_REVIEW
        HistoryExport.invalidate()
        #endif
    }
    var body: some Scene {
        WindowGroup {
            AppearanceHost {
                if onboardingDone { AppTabs(flow: flow) }
                else { OnboardingScreen { onboardingDone = true; SharedSettings.defaults.set(true, forKey: SharedSettings.networkNotice) } }
            }
        }.modelContainer(container)
    }
}

enum AppTab: Hashable { case scan, help, settings }
struct AppTabs: View {
    @State var flow: ScanFlow
    @State private var tab = AppTab.scan
    @State private var recovery = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var appColorScheme
    var body: some View {
        TabView(selection: $tab) {
            Tab(L10n.t("scan.title", .preferred), systemImage: "viewfinder", value: .scan) { ScannerScreen(flow: flow) }
            Tab(L10n.t("nav.help", .preferred), systemImage: "lifepreserver", value: .help) { NavigationStack { HelpScreen() } }
            if #available(iOS 27, *) {
                Tab(L10n.t("set.title", .preferred), systemImage: "gearshape", value: .settings, role: .prominent) { SettingsScreen(flow: flow) }
            } else {
                Tab(L10n.t("set.title", .preferred), systemImage: "gearshape", value: .settings) { SettingsScreen(flow: flow) }
            }
        }
        // Glass can be dark over the camera even in light mode. Use the system's
        // foreground so the selected tab adapts to the bar, not the page palette.
        .tint(.primary)
        .toolbarColorScheme(tab == .scan ? .dark : appColorScheme, for: .tabBar)
        .modifier(ScanResultPresentation(flow: flow, recovery: $recovery))
        .onChange(of: tab) { _, value in flow.scannerVisible = value == .scan; flow.cancelImport() }
        .onChange(of: phase) { _, value in
            flow.appActive = value == .active
            if value == .active { HistoryStore.importInbox(in: context) } else { flow.cancelImport() }
            flow.updateCamera()
        }
        .onAppear {
            flow.modelContext = context; flow.scannerVisible = tab == .scan; flow.appActive = phase == .active
            flow.onRecoveryHelp = { recovery = true }
            flow.onShowScanner = { tab = .scan }
            HistoryStore.importInbox(in: context); flow.updateCamera()
            #if DEBUG || DESIGN_REVIEW
            DebugLaunch.run(flow)
            if let openTab = DebugLaunch.openTab { tab = openTab }
            #endif
        }
    }
}

struct OnboardingScreen: View {
    let done: () -> Void
    @State private var page = 0
    @Environment(\.bqDesign) private var design
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Label("Bezpečné QR", systemImage: "viewfinder").font(.headline); Spacer()
                }
                Image(systemName: page == 0 ? "qrcode.viewfinder" : "camera")
                    .font(.system(size: 72, weight: .light)).frame(maxWidth: .infinity, minHeight: 150)
                    .background(design.accent, in: RoundedRectangle(cornerRadius: design.radius))
                    .accessibilityHidden(true)
                DesignHeading(L10n.t(page == 0 ? "onb.1.title" : "onb.2.title", .preferred),
                              subtitle: L10n.t(page == 0 ? "onb.1.text" : "onb.2.text", .preferred))
                if page == 0 {
                    ForEach(["onb.1.b1", "onb.1.b2", "onb.1.b3"], id: \.self) { Text(L10n.t($0, .preferred)).font(.body) }
                    Text(L10n.t("onb.privacyNote", .preferred)).font(.footnote).foregroundStyle(.secondary)
                }
                Button(L10n.t(page == 0 ? "onb.continue" : "onb.allowCamera", .preferred)) {
                    if page == 0 { withAnimation(reduced ? nil : .easeInOut(duration: 0.2)) { page = 1 } }
                    else { Task { _ = await CameraController.requestAccess(); done() } }
                }.buttonStyle(PrimaryButtonStyle())
                Button(L10n.t(page == 0 ? "onb.skip" : "onb.notNow", .preferred), action: done)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.padding(design.padding)
        }.background(design.background).foregroundStyle(design.ink)
    }
}
