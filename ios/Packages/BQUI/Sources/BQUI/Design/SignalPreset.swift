import BQCore
import SwiftUI

public enum SignalPreset: String, CaseIterable, Identifiable, Sendable {
    case current, poster, fade, type
    public var id: String { rawValue }
    public var title: String { L10n.t("preset." + rawValue, .preferred) }
    public var descriptionText: String { L10n.t("preset." + rawValue + ".description", .preferred) }
}

public enum ResultPresentationStyle: String, CaseIterable, Identifiable, Sendable {
    case popup, sheet, fullPage
    public var id: String { rawValue }
    public var title: String { L10n.t("presentation." + rawValue, .preferred) }
}

private struct SignalPresetKey: EnvironmentKey { static let defaultValue = SignalPreset.fade }
private struct ResultPresentationKey: EnvironmentKey { static let defaultValue = ResultPresentationStyle.sheet }
public extension EnvironmentValues {
    var bqSignalPreset: SignalPreset { get { self[SignalPresetKey.self] } set { self[SignalPresetKey.self] = newValue } }
    var bqResultPresentation: ResultPresentationStyle { get { self[ResultPresentationKey.self] } set { self[ResultPresentationKey.self] = newValue } }
}

/// The normal Release explicitly ignores internal-review preferences.
public struct ReviewAppearance: Equatable, Sendable {
    public let preset: SignalPreset
    public let presentation: ResultPresentationStyle
    public let scoreChart: ScoreChartStyle
    public let fadeTreatment: FadeTreatment
    public let statusBar: ReviewStatusBar
    public init(preset: String?, presentation: String?, scoreChart: String? = nil,
                fadeTreatment: String? = nil, statusBar: String? = nil, enabled: Bool) {
        self.preset = .fade
        self.presentation = .sheet
        self.scoreChart = enabled ? ScoreChartStyle(rawValue: scoreChart ?? "") ?? .spectrum : .spectrum
        self.fadeTreatment = .vivid
        self.statusBar = .immersive
    }
}
