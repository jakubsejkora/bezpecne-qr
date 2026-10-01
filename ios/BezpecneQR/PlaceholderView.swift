import SwiftUI

/// Temporary first screen. It exists to prove signing, extension embedding and TestFlight
/// delivery before the scanner is built on the signed-off design.
struct PlaceholderView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.31, green: 0.55, blue: 1.0), Color(red: 0.12, green: 0.23, blue: 0.54)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 76, weight: .semibold))
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
                Text("Bezpečné QR")
                    .font(.largeTitle.bold())
                Text("Testovací sestavení")
                    .font(.title3.weight(.semibold))
                Text("Ověřujeme podepisování a doručení přes TestFlight. Skener přijde v další verzi.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Text("Verze \(version)")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .bqGlass()
            }
            .foregroundStyle(.white)
            .padding(28)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, material fallback on iOS 18.
    @ViewBuilder
    func bqGlass(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

#Preview {
    PlaceholderView()
}
