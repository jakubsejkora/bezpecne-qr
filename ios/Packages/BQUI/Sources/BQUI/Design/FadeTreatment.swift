import BQCore
import SwiftUI

public enum FadeTreatment: String, CaseIterable, Identifiable, Sendable {
    case vivid, softWash
    public var id: String { rawValue }
    public var title: String { L10n.t("fade." + rawValue, .preferred) }
    public var descriptionText: String { L10n.t("fade." + rawValue + ".description", .preferred) }
}

public enum ReviewStatusBar: String, CaseIterable, Identifiable, Sendable {
    case visible, immersive
    public var id: String { rawValue }
    public var title: String { L10n.t("statusBar." + rawValue, .preferred) }
}

private struct FadeTreatmentKey: EnvironmentKey { static let defaultValue = FadeTreatment.vivid }
private struct ReviewStatusBarKey: EnvironmentKey { static let defaultValue = ReviewStatusBar.visible }
private struct ReviewStatusControlKey: EnvironmentKey { static let defaultValue = false }
public extension EnvironmentValues {
    var bqFadeTreatment: FadeTreatment { get { self[FadeTreatmentKey.self] } set { self[FadeTreatmentKey.self] = newValue } }
    var bqReviewStatusBar: ReviewStatusBar { get { self[ReviewStatusBarKey.self] } set { self[ReviewStatusBarKey.self] = newValue } }
    /// Only app-owned scan/result containers offer the status-bar comparison. The extension does not.
    var bqReviewStatusControl: Bool { get { self[ReviewStatusControlKey.self] } set { self[ReviewStatusControlKey.self] = newValue } }
}

/// Intrinsic text height, independent of scroll position. No layout spacer or moving frame is used.
struct FadeHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
public extension View {
    func measureFadeHeader() -> some View {
        background {
            GeometryReader { proxy in Color.clear.preference(key: FadeHeaderHeightKey.self, value: proxy.size.height) }
        }
    }
    func scannerFadeBackground() -> some View {
        backgroundPreferenceValue(FadeHeaderHeightKey.self) { height in
            SignalScannerBackdrop(headerHeight: height)
        }
    }
}

/// Page-compatible ink remains readable at *every* point, including content adjoining the header.
/// Both treatments are opaque blends with the page, so Reduce Transparency never reveals a layer.
struct FadeSurface {
    let page: SignalPalette.RGB
    let ink: SignalPalette.RGB
    let top: SignalPalette.RGB
    init(base: SignalPalette.RGB, treatment: FadeTreatment, dark: Bool, increasedContrast: Bool = false) {
        page = SignalPalette.RGB(dark ? 0x101210 : 0xF3F4F0)
        ink = SignalPalette.RGB(dark ? 0xF5F4EF : 0x171816)
        let minimum = increasedContrast ? 7.0 : 4.6
        var strength = treatment == .softWash ? 0.28 : 1.0
        // Use the strongest readable shade of this exact score colour, never a different hue.
        while page.mixed(with: base, fraction: strength).contrast(with: ink) < minimum && strength > 0 {
            strength = max(0, strength - 0.005)
        }
        top = page.mixed(with: base, fraction: strength)
    }
    func sample(_ position: Double) -> SignalPalette.RGB {
        if position >= 1 { return page }
        return top.mixed(with: page, fraction: SignalPalette.smooth(position))
    }
    var gradient: LinearGradient {
        LinearGradient(stops: (0...64).map { .init(color: sample(Double($0) / 64).color, location: Double($0) / 64) },
                       startPoint: .top, endPoint: .bottom)
    }
}

struct ResultFadeBackdrop: View {
    let base: SignalPalette.RGB
    let headerHeight: CGFloat
    @Environment(\.bqFadeTreatment) private var treatment
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { proxy in
            // SheetChrome is 44 pt + 16 pt vertical padding; the content has 2 pt top padding.
            let top = proxy.safeAreaInsets.top
            FadeSurface(base: base, treatment: treatment, dark: scheme == .dark, increasedContrast: contrast == .increased).gradient
                .frame(height: top + 62 + headerHeight + 144)
                .offset(y: -top)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct SignalScannerBackdrop: View {
    let headerHeight: CGFloat
    @Environment(\.bqDesign) private var design
    @Environment(\.bqSignalPreset) private var preset
    @Environment(\.bqFadeTreatment) private var treatment
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        if design == .signal && preset == .fade {
            GeometryReader { proxy in
                let top = proxy.safeAreaInsets.top
                let textBottom = top + headerHeight
                let height = textBottom + 144
                let base = SignalPalette.RGB(0xD8FA3D)
                let colour = treatment == .vivid ? base : base.mixed(with: .init(0x000000), fraction: 0.88)
                if opaque || contrast == .increased {
                    colour.color.frame(height: textBottom).offset(y: -top)
                } else {
                    LinearGradient(stops: (0...96).map { index in
                        let y = Double(index) / 96 * height
                        let strength = ScannerFadeCurve.strength(at: y, textBottom: textBottom)
                        return .init(color: colour.color.opacity(strength), location: Double(index) / 96)
                    }, startPoint: .top, endPoint: .bottom)
                    .frame(height: height).offset(y: -top)
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

enum ScannerFadeCurve {
    /// Smooth shared scrim: at least 82% coverage behind text on both white and black footage.
    /// Matching slopes at the text boundary avoids a solid panel followed by a visible fade strip.
    static func strength(at y: Double, textBottom: Double) -> Double {
        let h = max(1, textBottom)
        if y <= h { return 1 - 0.18 * pow(max(0, y) / h, 2) }
        let t = min(1, (y - h) / 144)
        let slope = max(-1.0, -0.36 / h * 144)
        return max(0, (2 * t * t * t - 3 * t * t + 1) * 0.82 + (t * t * t - 2 * t * t + t) * slope)
    }
}

public struct FadeTreatmentSwatch: View {
    let treatment: FadeTreatment
    @Environment(\.colorScheme) private var scheme
    public init(_ treatment: FadeTreatment) { self.treatment = treatment }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aa").font(.system(size: 32, weight: .heavy))
                Spacer()
                Text("42").font(.system(size: 24, weight: .heavy))
            }
            RiskScoreChart(score: 42, muted: false, style: .rail, compact: true)
            RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.2)).frame(width: 65, height: 4)
        }.padding(14).frame(height: 126)
            .background(FadeSurface(base: SignalPalette.color(at: 42), treatment: treatment, dark: scheme == .dark).gradient)
            .foregroundStyle(DesignDirection.signal.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
}
