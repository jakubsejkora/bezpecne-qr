#if DEBUG || DESIGN_REVIEW
import BQCore
import BQServices
import BQUI
import SwiftUI

struct ScoreChartLab: View {
    let flow: ScanFlow
    @AppStorage(SharedSettings.scoreChart, store: SharedSettings.defaults) private var selection = "spectrum"
    @Environment(\.bqDesign) private var design
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var score = 42.0
    @State private var incomplete = false
    private let lang = Language.preferred
    private var current: ScoreChartStyle { ScoreChartStyle(rawValue: selection) ?? .spectrum }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("scoreChart.try", lang)).font(.title2.bold())
                    Text(L10n.t("scoreChart.note", lang)).font(.subheadline).foregroundStyle(design.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.t(incomplete ? "summary.provisional" : "scoreChart.sample", lang)).font(.subheadline)
                        Spacer(minLength: 8)
                        Text("\(Int(score))/100").font(.title2.bold()).monospacedDigit()
                    }
                    Slider(value: $score, in: 0...100) {
                        Text(L10n.t("scoreChart.sample", lang))
                    }.accessibilityValue(L10n.t("a11y.meterValue", ["score": String(Int(score))], lang))
                        .accessibilityIdentifier("scoreChart.sample")
                    Toggle(L10n.t("scoreChart.incomplete", lang), isOn: $incomplete)
                        .font(.subheadline).accessibilityIdentifier("scoreChart.incomplete")
                }
                LazyVGrid(columns: textSize.isAccessibilitySize ? [GridItem(.flexible())] :
                            [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(ScoreChartStyle.allCases) { style in
                        Button { selection = style.rawValue } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(style.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: current == style ? "checkmark.circle.fill" : "circle")
                                        .font(.body).accessibilityHidden(true)
                                }
                                RiskScoreChart(score: Int(score), muted: incomplete, style: style, compact: true)
                                    .frame(height: 56)
                            }
                            .padding(14).foregroundStyle(design.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(design.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(current == style ? design.ink : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(style.title)
                            .accessibilityHint(style.descriptionText)
                            .accessibilityAddTraits(current == style ? .isSelected : [])
                            .accessibilityIdentifier("scoreChart.option." + style.rawValue)
                    }
                }
                Text(current.descriptionText).font(.subheadline).foregroundStyle(design.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    resultButton("scoreChart.caution", sample: "url-free-hosting")
                    Divider()
                    resultButton("scoreChart.danger", sample: "url-parking-fake")
                }.padding(.horizontal, 16).background(design.surface, in: RoundedRectangle(cornerRadius: 14))
            }.padding(20)
        }
        .background(design.background)
        .tint(design.ink)
        .navigationTitle(L10n.t("scoreChart.title", lang)).navigationBarTitleDisplayMode(.inline)
    }

    private func resultButton(_ key: String, sample id: String) -> some View {
        Button {
            guard let sample = DebugSamplesScreen.samples.first(where: { $0.id == id }) else { return }
            SharedSettings.defaults.set("signal", forKey: SharedSettings.design)
            DebugSamplesScreen.replay(sample, in: flow, live: false)
        } label: {
            HStack(spacing: 12) {
                Label(L10n.t(key, lang), systemImage: "play.circle")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold())
            }.font(.subheadline.weight(.semibold)).frame(minHeight: 50)
        }.buttonStyle(.plain).accessibilityIdentifier(key)
    }
}
#endif
