import BQCore
import SwiftUI

public struct SignalScannerHeading: View {
    @Environment(\.bqSignalPreset) private var preset
    @Environment(\.bqFadeTreatment) private var fade
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var opaque
    public init() {}
    private let lime = DesignDirection.signal.accent
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lang.t("scan.aimTitle"))
                    .font(.system(preset == .current ? .title2 : .title, weight: .heavy))
                    .tracking(preset == .current ? 0 : -0.7)
                if !typeSize.isAccessibilitySize {
                    Text(lang.t("scan.aimSubtitle")).font(.subheadline.weight(.medium))
                }
                if preset == .type { Rectangle().fill(lime).frame(height: 3).padding(.top, 9).accessibilityHidden(true) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(preset == .current ? 16 : 22).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(preset == .type || (preset == .fade && fade == .softWash) ? .white : DesignDirection.signal.accentInk)
            .background {
                if preset != .fade { preset == .type ? Color.black.opacity(opaque ? 1 : 0.88) : lime }
            }
        }.clipShape(RoundedRectangle(cornerRadius: preset == .current ? 14 : 0))
    }
}

/// A compact native preview of the layout, kept separate from replayable risk fixtures.
public struct SignalPresetSwatch: View {
    public let preset: SignalPreset
    @Environment(\.bqLanguage) private var lang
    public init(_ preset: SignalPreset) { self.preset = preset }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aa").font(.system(size: 35, weight: .heavy)).tracking(-2)
                Spacer()
                Text("42").font(.system(size: 23, weight: .heavy))
            }.padding(13)
                .background(preset == .fade ? Color.clear : preset == .type ? Color.white : DesignDirection.signal.accent)
            Rectangle().fill(SignalPalette.gradient).frame(height: preset == .type ? 4 : 8)
                .padding(.horizontal, preset == .type ? 13 : 0)
            Spacer(minLength: 0)
            Rectangle().fill(.black.opacity(0.18)).frame(width: 80, height: 3).padding(13)
        }
        .foregroundStyle(.black).frame(height: 118)
        .background {
            if preset == .fade { FadeSurface(base: .init(0xD8FA3D), treatment: .vivid, dark: false).gradient }
            else { Color.white }
        }
        .clipShape(RoundedRectangle(cornerRadius: preset == .current ? 14 : 2))
        .accessibilityHidden(true)
    }
}
