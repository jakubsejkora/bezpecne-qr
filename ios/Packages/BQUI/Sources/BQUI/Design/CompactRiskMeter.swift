import BQCore
import SwiftUI

struct CompactRiskMeter: View {
    let score: Int
    let muted: Bool
    @Environment(\.bqLanguage) private var lang
    private var tone: Tone { muted ? .incomplete : score >= 60 ? .danger : score >= 25 ? .caution : .safe }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(lang.t("meter.label")).font(.footnote)
                Spacer(minLength: 8)
                Text("\(score)/100").font(.subheadline.bold()).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BQColor.fill)
                    Capsule().fill(tone.color).frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, score))) / 100))
                }
            }.frame(height: 4).accessibilityHidden(true)
            Text(lang.t(muted ? "meter.muted" : "meter.note", ["score": String(score)]))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(BQColor.label).padding(.vertical, 12).accessibilityElement(children: .combine)
    }
}
