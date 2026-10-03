import BQCore
import SwiftUI

/// "Výtah ze stránky": an inert, native extract of the already-fetched page — text, highlighted
/// small print, the fields and buttons it shows. Nothing is loaded and nothing can be submitted.
struct PageExtractView: View {
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        let a = model.analysis
        let page = a.inspection?.page
        VStack(alignment: .leading, spacing: 0) {
            Notice(icon: "eye", tone: .info) {
                Text(Typo.prose(lang.t("prev.note"), lang)).fixedSize(horizontal: false, vertical: true)
            }
            .blockGap()

            if let page {
                VStack(alignment: .leading, spacing: 0) {
                    if let title = page.title {
                        Claim(caption: lang.t("prev.claim"), text: lang.quoted(title))
                            .padding(.top, -12)
                            .padding(.bottom, 4)
                    }
                    let lines = Array(page.extract.enumerated())
                    ForEach(lines, id: \.offset) { index, line in
                        ExtractLine(line: Self.classify(line, highlighted: page.offer?.highlight.contains(index) ?? false))
                        if index < lines.count - 1 {
                            BQColor.separator.frame(height: 1)
                        }
                    }
                }
                .bqCard()
                .blockGap()
                if !page.asks.isEmpty {
                    SubHeading(text: lang.t("prev.fields"), top: 6)
                        .padding(.horizontal, 6)
                    AsksChips(asks: page.asks, allCaution: true)
                        .padding(.horizontal, 2)
                        .padding(.top, 4)
                        .blockGap()
                }
            } else {
                Notice(icon: Symbol.info) {
                    Text(lang.t("prev.none")).fixedSize(horizontal: false, vertical: true)
                }
                .blockGap()
            }

            VStack(spacing: 10) {
                Button {
                    model.route = .result
                } label: {
                    ButtonLabel(title: lang.t("common.back"), icon: nil)
                }
                .buttonStyle(BQButtonStyle(kind: .primary))
                if let url = a.openURL {
                    if a.band == .danger {
                        HoldAction(hold: ActionPlan.Hold(
                            id: "open", title: lang.t("act.hold"), kind: .open, action: .open(url),
                            alternativeTitle: lang.t("act.holdAlt"), confirmTitle: lang.t("alert.openTitle"),
                            confirmMessage: lang.t("alert.openText"), confirmButton: lang.t("alert.open")), model: model)
                    } else {
                        Button {
                            model.perform(.open(url))
                        } label: {
                            ButtonLabel(title: lang.t("act.openAnyway"), icon: nil)
                        }
                        .buttonStyle(BQButtonStyle(kind: .secondary))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    enum Line: Equatable {
        case text(String)
        case highlighted(String)
        /// `[ Pokračovat ]` — a button on the page.
        case button(String)
        /// `Telefonní číslo: [          ]` — an input field.
        case field(String)
    }

    static func classify(_ raw: String, highlighted: Bool) -> Line {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("["), line.hasSuffix("]") {
            let label = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            return .button(label)
        }
        if line.contains(/:\s*\[\s*\]$/) || line.contains(/\[\s+\]/) {
            let label = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? line
            return .field(label.trimmingCharacters(in: .whitespaces))
        }
        return highlighted ? .highlighted(line) : .text(line)
    }
}

private struct ExtractLine: View {
    var line: PageExtractView.Line
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        Group {
            switch line {
            case .text(let s):
                Text(s)
                    .bqFont(15.5, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.label)
            case .highlighted(let s):
                HighlightedText(text: s)
                    .bqFont(15.5, .bold, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.label)
                    .accessibilityLabel(s)
            case .button(let s):
                placeholder(icon: "hand.tap", text: s, kind: lang.t("a11y.pageButton"))
            case .field(let s):
                placeholder(icon: "pencil", text: s, kind: lang.t("a11y.inputField"))
            }
        }
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }

    private func placeholder(icon: String, text: String, kind: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
        }
        .bqFont(14, relativeTo: .subheadline)
        .foregroundStyle(BQColor.label2)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BQColor.label3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(kind)
    }
}
