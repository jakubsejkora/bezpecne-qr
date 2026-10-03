import SwiftUI

/// A short message after an action ("Zkopírováno", "Uloženo do Fotek") on a solid capsule.
struct ToastView: View {
    var toast: ResultModel.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .accessibilityHidden(true)
            Text(toast.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bqFont(15, .semibold, relativeTo: .subheadline)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(toast.isError ? Tone.danger.strong : BQColor.toast, in: .capsule)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Confetti — only after a successful contact save, never with Reduce Motion.
struct ConfettiView: View {
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    private struct Piece {
        var x: Double
        var delay: Double
        var spin: Double
        var drift: Double
        var color: Color
        var size: CGSize
    }

    private static let pieces: [Piece] = {
        var generator = SplitMix(seed: 0xB0D1_1C)
        let colors = [0xFF375F, 0x0A84FF, 0x30D158, 0xFFD60A, 0xBF5AF2, 0xFF9F0A].map { BQColor.hex(UInt32($0)) }
        return (0..<70).map { i in
            Piece(x: generator.unit(), delay: generator.unit() * 0.35, spin: generator.unit() * 180,
                  drift: (generator.unit() - 0.5) * 60, color: colors[i % colors.count],
                  size: CGSize(width: 8, height: 13))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            Canvas { canvas, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                for piece in Self.pieces {
                    let p = min(max((t - piece.delay) / 1.6, 0), 1)
                    guard p > 0, p < 1 else { continue }
                    let eased = 1 - pow(1 - p, 2.2)
                    let x = piece.x * size.width + piece.drift * sin(p * .pi * 2)
                    let y = -12 + (size.height + 40) * eased
                    var c = canvas
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(piece.spin + 540 * p))
                    c.opacity = 1 - 0.2 * p
                    c.fill(Path(roundedRect: CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                                    width: piece.size.width, height: piece.size.height), cornerRadius: 2),
                           with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            let begin = Date()
            start = begin
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                if start == begin { start = nil }
            }
        }
    }
}

/// A tiny deterministic generator so the confetti looks the same every time.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
