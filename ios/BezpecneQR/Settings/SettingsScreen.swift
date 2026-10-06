import BQCore
import BQServices
import BQUI
import SwiftData
import SwiftUI

struct SettingsScreen: View {
    let flow: ScanFlow
    @AppStorage(SharedSettings.history, store: SharedSettings.defaults) private var historyEnabled = true
    @AppStorage(SharedSettings.pageFetch, store: SharedSettings.defaults) private var pageFetch = true
    @AppStorage(SharedSettings.domainChecks, store: SharedSettings.defaults) private var domainChecks = true
    @Environment(\.bqDesign) private var design
    #if DEBUG || DESIGN_REVIEW
    @State private var labOpen = false
    @State private var historyOpen = false
    #endif
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DesignHeading(L10n.t("set.title", .preferred), subtitle: L10n.t("set.intro", .preferred))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                #if DEBUG || DESIGN_REVIEW
                Section {
                    NavigationLink { DesignLab(flow: flow) } label: {
                        Label(L10n.t("lab.title", .preferred), systemImage: "slider.horizontal.3").font(.headline)
                    }
                } footer: { Text(L10n.t("lab.summary", .preferred)) }
                #endif
                Section {
                    NavigationLink { HistoryScreen(flow: flow, close: {}).modifier(DesignListModifier()) } label: {
                        Label(L10n.t("hist.title", .preferred), systemImage: "clock")
                    }
                    Toggle(L10n.t("set.historyOn", .preferred), isOn: $historyEnabled)
                } header: { Text(L10n.t("set.history", .preferred)) }
                  footer: { Text(L10n.t("set.historyFoot", .preferred)) }
                Section(L10n.t("set.checks", .preferred)) {
                    Toggle(isOn: $pageFetch) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("set.pageFetch", .preferred))
                            Text(L10n.t("set.pageFetchSub", .preferred)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $domainChecks) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("set.domain", .preferred))
                            Text(L10n.t("set.domainSub", .preferred)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NavigationLink { PrivacyScreen() } label: { Label(L10n.t("set.privacy", .preferred), systemImage: "hand.raised") }
                    NavigationLink { AboutScreen() } label: { Label(L10n.t("set.about", .preferred), systemImage: "info.circle") }
                }
                Section {
                    VStack(spacing: 14) {
                        Text(L10n.t("credits.creator", .preferred)).font(.headline)
                        #if DEBUG || DESIGN_REVIEW
                        Text(L10n.t("credits.coffee", .preferred)).font(.subheadline)
                        Text(L10n.t("credits.support", .preferred)).font(.footnote).foregroundStyle(.secondary)
                        Link(L10n.t("credits.visit", .preferred), destination: URL(string: "https://atypika.cz/")!)
                            .font(.subheadline.weight(.semibold)).tint(.blue).frame(minHeight: 44).accessibilityIdentifier("credits.shop")
                        #endif
                        Text("Bezpečné QR · " + AppInfo.version).font(.caption).foregroundStyle(.secondary)
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 28)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }

            }.modifier(DesignListModifier()).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            #if DEBUG || DESIGN_REVIEW
                .navigationDestination(isPresented: $labOpen) {
                    if UserDefaults.standard.string(forKey: "BQDebugOpen") == "scores" { ScoreChartLab(flow: flow) }
                    else { DesignLab(flow: flow) }
                }
                .navigationDestination(isPresented: $historyOpen) { HistoryScreen(flow: flow, close: {}).modifier(DesignListModifier()) }
                .onAppear { if UserDefaults.standard.string(forKey: "BQDebugOpen") == "history" { historyOpen = true }; if ["lab", "sharing", "scores"].contains(UserDefaults.standard.string(forKey: "BQDebugOpen") ?? "") { labOpen = true } }
            #endif
        }.onChange(of: historyEnabled) { _, enabled in HistoryStore.invalidatePending(enabled: enabled) }
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
    @AppStorage(SettingsKey.historyEnabled, store: SharedSettings.defaults) private var historyEnabled = true
    @State private var confirmClear = false
    private let lang = Language.preferred

    var body: some View {
        List {
            Section {
                DesignHeading(L10n.t("hist.title", lang), subtitle: L10n.t("hist.intro", lang))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            #if DEBUG || DESIGN_REVIEW
            if !history.isEmpty {
                Section {
                    NavigationLink { HistoryExportScreen() } label: {
                        Label(L10n.t("hist.export", lang), systemImage: "square.and.arrow.up")
                    }
                }
            }
            #endif
            if !historyEnabled && history.isEmpty {
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
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
