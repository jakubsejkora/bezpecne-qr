import Foundation

/// Preferences shared by the app and its image extension. Explicit existing choices win on migration.
public enum SharedSettings {
    public static let group = "group.cz.bezpecneqr.app"
    public static let history = "historyEnabled"
    public static let pageFetch = "pageFetch"
    public static let domainChecks = "domainChecks"
    public static let networkNotice = "networkNoticeAccepted"
    public static let design = "designDirection"
    public static let capture = "captureStyle"
    public static let aim = "aimGuideStyle"
    public static let signalPreset = "reviewSignalPreset"
    public static let resultPresentation = "reviewResultPresentation"
    public static let scoreChart = "reviewScoreChart"
    public static let fadeTreatment = "reviewFadeTreatment"
    public static let statusBar = "reviewStatusBar"
    public static let defaultDesign = "signal"
    public static let defaultAim = "roundedCorners"
    public static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    public static func migrate(from old: UserDefaults = .standard, to shared: UserDefaults = defaults) {
        guard !shared.bool(forKey: "preferencesMigratedV1") else { return }
        for key in [history, pageFetch, domainChecks] {
            // The extension may have been used before the upgraded app's first launch.
            guard shared.object(forKey: key) == nil else { continue }
            shared.set(old.object(forKey: key) ?? true, forKey: key)
        }
        if old.bool(forKey: "onboardingDone") { shared.set(true, forKey: networkNotice) }
        shared.set(true, forKey: "preferencesMigratedV1")
    }

    public static func enabled(_ key: String, in store: UserDefaults = defaults) -> Bool {
        store.object(forKey: key) == nil ? true : store.bool(forKey: key)
    }

    public static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
}
