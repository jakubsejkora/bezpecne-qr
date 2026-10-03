import BQCore
import SwiftUI

/// The bold business card (`.bizcard`): gradient wash, big initials, essentials on the front and
/// warnings attached to the affected field. "Další údaje" holds the rest.
struct ContactCard: View {
    var info: ContactInfo
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bqSnapshot) private var snapshot
    @State private var dealt = false
    @ScaledMetric(relativeTo: .subheadline) private var rowIconWidth: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if reduceMotion || snapshot {
                    front
                } else {
                    // Flips in like a card dealt onto the table. A plain state change with a spring
                    // always settles flat (a keyframe animator left the card rotated on iOS 27).
                    front
                        .rotation3DEffect(.degrees(dealt ? 0 : -70), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .scaleEffect(dealt ? 1 : 0.92)
                        .opacity(dealt ? 1 : 0)
                        .onAppear {
                            withAnimation(.smooth(duration: 0.8)) { dealt = true }
                        }
                }
            }
            .blockGap()
            if !moreRows.isEmpty {
                Disclosure(title: lang.t("contact.more"), isExpanded: Binding(
                    get: { model.contactMoreExpanded }, set: { model.contactMoreExpanded = $0 })) {
                    KeyValueList(rows: moreRows, top: 0)
                        .padding(.bottom, 14)
                }
                .blockGap()
            }
        }
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.initials(info.name))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.white.opacity(0.22), in: .card(24))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
                .accessibilityHidden(true)
            Text(info.name)
                .bqFont(28, .bold, relativeTo: .title)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.bottom, 2)
            let role = [info.title, info.org].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !role.isEmpty {
                Text(role)
                    .bqFont(15.5, .semibold, relativeTo: .subheadline)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Image(systemName: row.icon)
                                .frame(width: rowIconWidth)
                                .accessibilityHidden(true)
                            Text(HostFormat.breakable(row.value))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(row.value)
                            if row.flagged {
                                Text(lang.t("band.caution"))
                                    .bqFont(12, .bold, relativeTo: .caption)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.25), in: .capsule)
                            }
                        }
                        .bqFont(15, .semibold, relativeTo: .subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(row.flagged ? BQColor.hex(0xFF5A3C, 0.92) : Color.white.opacity(0.16), in: .card(14))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 14)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BusinessCardWash(hue: Double(Format.hue(info.name))) }
        .clipShape(.card(26))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    private struct Row: Identifiable {
        var id: String { icon + value }
        var icon: String
        var value: String
        var flagged = false
    }

    private var rows: [Row] {
        info.tels.map { Row(icon: "phone", value: $0) }
            + info.emails.map { Row(icon: "envelope", value: $0) }
            + info.urls.map { Row(icon: "globe", value: $0, flagged: $0 == info.flaggedUrl) }
    }

    private var moreRows: [KeyValue] {
        var out: [KeyValue] = []
        if let address = info.address, !address.isEmpty {
            out.append(KeyValue(key: lang.t("contact.address"), value: address, keyIcon: "mappin.and.ellipse"))
        }
        if let birthday = info.birthday, !birthday.isEmpty {
            out.append(KeyValue(key: lang.t("contact.birthday"), value: Format.longDate(birthday, language: lang)))
        }
        if let note = info.note, !note.isEmpty {
            out.append(KeyValue(key: lang.t("contact.note"), value: note))
        }
        if !out.isEmpty {
            out.append(KeyValue(key: lang.t("contact.format"), value: info.format))
        }
        return out
    }

}

/// `linear-gradient(135deg, hsl(h 70% 46%), hsl(h+40 75% 38%))` with light and shade, as a mesh.
struct BusinessCardWash: View {
    var hue: Double

    var body: some View {
        let h = hue
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.55, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            .hsl(h, 70, 47), .hsl(h + 12, 72, 52), .hsl(h + 18, 72, 62),
            .hsl(h + 8, 70, 42), .hsl(h + 20, 72, 44), .hsl(h + 30, 74, 47),
            .hsl(h + 18, 72, 30), .hsl(h + 30, 74, 34), .hsl(h + 40, 75, 38),
        ])
        .overlay {
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
        }
    }
}

/// `details.more`: a card with a bold summary and a chevron that turns.
struct Disclosure<Content: View>: View {
    var title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @Environment(\.bqLanguage) private var lang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .bqFont(16, .bold, relativeTo: .callout)
                        .foregroundStyle(BQColor.label)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BQColor.label2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 15)
                .frame(minHeight: Metrics.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(lang.t(isExpanded ? "a11y.expanded" : "a11y.collapsed"))
            if isExpanded {
                content
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BQColor.card, in: .card(Metrics.detailsRadius))
    }
}
