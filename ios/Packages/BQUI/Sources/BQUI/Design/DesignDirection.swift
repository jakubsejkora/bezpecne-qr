import BQCore
import SwiftUI
import UIKit

public enum DesignDirection: String, CaseIterable, Identifiable, Sendable {
    case editorial, signal, precision, softContrast
    public var id: String { rawValue }
    public var title: String {
        switch self { case .editorial: "Editorial"; case .signal: "Signal"; case .precision: "Precision"; case .softContrast: "Soft Contrast" }
    }
    public var radius: CGFloat { switch self { case .editorial: 24; case .signal: 14; case .precision: 10; case .softContrast: 30 } }
    public var padding: CGFloat { self == .precision ? 18 : 22 }
    public var fontDesign: Font.Design { self == .softContrast ? .rounded : .default }
    public var headingWeight: Font.Weight { self == .signal ? .heavy : .bold }
    public var background: Color {
        switch self {
        case .editorial: Self.adaptive(0xF5F3ED, 0x171715)
        case .signal: Self.adaptive(0xF3F4F0, 0x101210)
        case .precision: Self.adaptive(0xF6F7F8, 0x111315)
        case .softContrast: Self.adaptive(0xF3F0EB, 0x211E1C)
        }
    }
    public var surface: Color { Self.adaptive(0xFFFFFF, self == .softContrast ? 0x302B28 : 0x252625) }
    public var ink: Color { Self.adaptive(0x171816, 0xF5F4EF) }
    public var inverse: Color { Self.adaptive(0xFFFFFF, 0x171816) }
    public var accent: Color {
        switch self {
        case .editorial: Self.adaptive(0xD7DBCB, 0x3A4134)
        case .signal: Self.adaptive(0xD8FA3D, 0xD8FA3D)
        case .precision: Self.adaptive(0xE3E7EA, 0x323B42)
        case .softContrast: Self.adaptive(0xDED5C6, 0x4C4237)
        }
    }
    public var accentInk: Color { self == .signal ? Color(red: 0.08, green: 0.10, blue: 0.04) : ink }
    public var buttonRadius: CGFloat { self == .precision ? 12 : self == .signal ? 16 : 30 }
    public var titleFont: Font { .system(.largeTitle, design: fontDesign, weight: headingWeight) }
    public var descriptionText: String { L10n.t("design." + rawValue, .preferred) }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}
private struct DesignKey: EnvironmentKey { static let defaultValue = DesignDirection.signal }
private struct ReviewControlsBox: @unchecked Sendable { let view: AnyView }
private struct ReviewControlsKey: EnvironmentKey { static let defaultValue: ReviewControlsBox? = nil }
public extension EnvironmentValues {
    var bqDesign: DesignDirection { get { self[DesignKey.self] } set { self[DesignKey.self] = newValue } }
    var bqReviewControls: AnyView? { get { self[ReviewControlsKey.self]?.view } set { self[ReviewControlsKey.self] = newValue.map { ReviewControlsBox(view: $0) } } }
}

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.bqDesign) private var design
    @Environment(\.accessibilityReduceMotion) private var reduced
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: design.fontDesign)).multilineTextAlignment(.center)
            .foregroundStyle(design.inverse)
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(design.ink, in: RoundedRectangle(cornerRadius: design.buttonRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduced ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct DesignListModifier: ViewModifier {
    @Environment(\.bqDesign) private var design
    public init() {}
    public func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(design.background)
            .tint(design.ink).fontDesign(design.fontDesign)
    }
}

public struct DesignHeading: View {
    public var title: String
    public var subtitle: String
    @Environment(\.bqDesign) private var design
    public init(_ title: String, subtitle: String) { self.title = title; self.subtitle = subtitle }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.largeTitle, weight: .bold)).tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(design.ink).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
