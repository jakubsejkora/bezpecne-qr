import BQCore
import SwiftUI

/// Calendar event: a calendar tile with month and day, the title, time and place.
struct EventCard: View {
    var info: EventInfo
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        VStack(alignment: .leading, spacing: 0) {
            layout {
                if let date = Format.parseISODate(info.start) {
                    CalendarTile(date: date)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.summary)
                        .bqFont(22, .bold, relativeTo: .title2)
                        .foregroundStyle(BQColor.label)
                        .fixedSize(horizontal: false, vertical: true)
                    if let when {
                        CardLabel(text: when)
                    }
                    if let location = info.location, !location.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "mappin.and.ellipse").imageScale(.small).accessibilityHidden(true)
                            Text(location).fixedSize(horizontal: false, vertical: true)
                        }
                        .bqFont(13, .semibold, relativeTo: .footnote)
                        .foregroundStyle(BQColor.label2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let description = info.description, !description.isEmpty {
                Claim(caption: nil, text: description)
            }
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
        .accessibilityElement(children: .combine)
    }

    /// "18:00–20:00" (the tile shows the date); all-day events say so.
    private var when: String? {
        guard let start = info.start else { return nil }
        guard let from = Format.time(start, language: lang) else { return lang.t("event.allDay") }
        if let to = Format.time(info.end, language: lang) { return "\(from)–\(to)" }
        return from
    }
}

/// `.cal-tile`: red month header and a big rounded day number.
struct CalendarTile: View {
    var date: Date
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(spacing: 0) {
            Text(format("LLL").uppercased(with: lang.locale))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(BQColor.calendarRed)
            Text(format("d"))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(BQColor.label)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .frame(width: 76)
        .background(BQColor.card2)
        .clipShape(.card(18))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(longDate)
    }

    private var longDate: String {
        let f = DateFormatter()
        f.locale = lang.locale
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return f.string(from: date)
    }

    private func format(_ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = lang.locale
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

/// Place on a map: an offline, drawn map snapshot with a pin (no map tiles are loaded).
struct GeoCard: View {
    var info: GeoInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MapSketch()
                .frame(height: 180)
                .clipShape(.card(18))
                .padding(.bottom, 10)
            if let label = info.label, !label.isEmpty {
                Text(label)
                    .bqFont(22, .bold, relativeTo: .title2)
                    .foregroundStyle(BQColor.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CardLabel(text: "\(lang.t("geo.coords")): \(Self.coordinate(info.lat)), \(Self.coordinate(info.lon))")
                .padding(.top, 2)
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }

    static func coordinate(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 6
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// The prototype's SVG map (360×180 viewBox), drawn natively and adapted to dark mode.
struct MapSketch: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bqSnapshot) private var snapshot
    @State private var dropped = false

    var body: some View {
        let dark = scheme == .dark
        Canvas { context, size in
            let sx = size.width / 360, sy = size.height / 180
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark ? BQColor.hex(0x1E2A22) : BQColor.hex(0xE8EFE3)))
            var river = Path()
            river.move(to: pt(0, 120))
            river.addCurve(to: pt(200, 120), control1: pt(80, 100), control2: pt(120, 150))
            river.addCurve(to: pt(360, 110), control1: pt(280, 90), control2: pt(320, 90))
            context.stroke(river, with: .color(dark ? BQColor.hex(0x2B4A6B) : BQColor.hex(0x9EC5F0)), lineWidth: 18 * sy)
            var roads = Path()
            roads.move(to: pt(40, 0)); roads.addLine(to: pt(90, 180))
            roads.move(to: pt(0, 60)); roads.addLine(to: pt(360, 40))
            roads.move(to: pt(250, 0)); roads.addLine(to: pt(220, 180))
            roads.move(to: pt(0, 150)); roads.addLine(to: pt(360, 170))
            context.stroke(roads, with: .color(dark ? BQColor.hex(0x3A4048) : .white), lineWidth: 7 * sy)
            let building = dark ? BQColor.hex(0x3B3833) : BQColor.hex(0xD7CFC0)
            context.fill(Path(CGRect(origin: pt(120, 60), size: CGSize(width: 60 * sx, height: 40 * sy))), with: .color(building))
            context.fill(Path(CGRect(origin: pt(200, 70), size: CGSize(width: 40 * sx, height: 30 * sy))), with: .color(building))
        }
        .overlay {
            GeometryReader { geo in
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, BQColor.calendarRed)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.45)
                    .offset(y: (reduceMotion || snapshot || dropped) ? 0 : -40)
                    .opacity((reduceMotion || snapshot || dropped) ? 1 : 0)
            }
        }
        .onAppear {
            guard !reduceMotion, !snapshot else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0.45).delay(0.2)) { dropped = true }
        }
        .accessibilityHidden(true)
    }
}
