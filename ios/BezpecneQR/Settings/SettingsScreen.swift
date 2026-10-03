import BQCore
import BQUI
import SwiftData
import SwiftUI

/// Settings: history (for family checks), internet checks, privacy, help and about.
struct SettingsScreen: View {
    let flow: ScanFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.date, order: .reverse) private var history: [ScanRecord]
    @AppStorage(SettingsKey.historyEnabled) private var historyEnabled = true
    @AppStorage(SettingsKey.pageFetch) private var pageFetch = true
    @AppStorage(SettingsKey.domainChecks) private var domainChecks = true
    private let lang = Language.preferred

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HistoryScreen(flow: flow, close: { dismiss() })
                    } label: {
                        SettingsRow(icon: "clock.arrow.circlepath", color: .gray, title: L10n.t("hist.title", [:], lang), value: "\(history.count)")
                    }
                    Toggle(L10n.t("set.historyOn", [:], lang), isOn: $historyEnabled)
                } header: {
                    Text(L10n.t("set.history", [:], lang))
                } footer: {
                    Text(L10n.t("set.historyFoot", [:], lang))
                }

                Section(L10n.t("set.checks", [:], lang)) {
                    Toggle(isOn: $pageFetch) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("set.pageFetch", [:], lang))
                            Text(L10n.t("set.pageFetchSub", [:], lang)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $domainChecks) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("set.domain", [:], lang))
                            Text(L10n.t("set.domainSub", [:], lang)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L10n.t("set.privacy", [:], lang)) {
                    NavigationLink {
                        PrivacyScreen()
                    } label: {
                        SettingsRow(icon: "hand.raised.fill", color: .blue, title: L10n.t("set.privacy", [:], lang))
                    }
                }

                Section(L10n.t("set.help", [:], lang)) {
                    NavigationLink {
                        OperatorGuideScreen()
                    } label: {
                        SettingsRow(icon: "antenna.radiowaves.left.and.right", color: .green, title: L10n.t("set.operator", [:], lang))
                    }
                    NavigationLink {
                        RecoveryGuideScreen()
                    } label: {
                        SettingsRow(icon: "lifepreserver.fill", color: .orange, title: L10n.t("set.recovery", [:], lang))
                    }
                }

                Section {
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        SettingsRow(icon: "heart.fill", color: .pink, title: L10n.t("set.about", [:], lang), value: AppInfo.version)
                    }
                    #if DEBUG
                    NavigationLink {
                        DebugSamplesScreen(flow: flow, close: { dismiss() })
                    } label: {
                        SettingsRow(icon: "ladybug.fill", color: .purple, title: L10n.t("set.debug", [:], lang))
                    }
                    #endif
                } footer: {
                    Text("Bezpečné QR \(AppInfo.version) · \(L10n.t("set.licenseVal", [:], lang))")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .navigationTitle(L10n.t("set.title", [:], lang))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("act.close", [:], lang)) { dismiss() }
                }
            }
        }
    }
}

struct SettingsRow: View {
    var icon: String
    var color: Color
    var title: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
            if let value {
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - History

struct HistoryScreen: View {
    let flow: ScanFlow
    let close: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.date, order: .reverse) private var history: [ScanRecord]
    @AppStorage(SettingsKey.historyEnabled) private var historyEnabled = true
    @State private var confirmClear = false
    private let lang = Language.preferred

    var body: some View {
        List {
            if !historyEnabled {
                ContentUnavailableView(L10n.t("hist.disabled", [:], lang), systemImage: "clock.badge.xmark")
            } else if history.isEmpty {
                ContentUnavailableView(L10n.t("hist.empty", [:], lang), systemImage: "qrcode")
            } else {
                Section {
                    ForEach(history) { record in
                        Button {
                            close()
                            flow.recheck(record)
                        } label: {
                            HistoryRow(record: record)
                        }
                        .disabled(record.payload == nil)
                        .accessibilityHint(record.payload == nil ? "" : L10n.t("hist.recheck", [:], lang))
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(history[i]) }
                        try? modelContext.save()
                    }
                }
                Section {
                    Button(L10n.t("hist.clear", [:], lang), role: .destructive) { confirmClear = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L10n.t("hist.title", [:], lang))
        .confirmationDialog(L10n.t("hist.clear", [:], lang), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.t("hist.clear", [:], lang), role: .destructive) { HistoryStore.clear(in: modelContext) }
        }
    }
}

struct HistoryRow: View {
    let record: ScanRecord
    private let lang = Language.preferred

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(BandColor.color(for: Band(rawValue: record.band) ?? .info))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.payload == nil && record.title.isEmpty ? L10n.t("hist.redacted", [:], lang) : record.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(L10n.t("type.\(record.type)", [:], lang)) · \(L10n.t("band.\(record.band == "info" ? "infoChip" : record.band)", [:], lang)) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let score = record.score {
                Text("\(score)")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.t("meter.label", [:], lang) + " \(score)")
            }
        }
        .padding(.vertical, 2)
    }
}

/// Band colours for small indicators outside the result sheet.
enum BandColor {
    static func color(for band: Band) -> Color {
        switch band {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        case .incomplete: return .gray
        case .info: return .blue
        }
    }
}
