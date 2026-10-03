import BQCore
import BQUI
import SwiftUI

/// What the app does with data. Community sharing (the opt-in backend) is not built yet,
/// so nothing is sent to the project team.
struct PrivacyScreen: View {
    private let lang = Language.preferred

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("priv.p1", [:], lang))
                    Text(L10n.t("priv.p2", [:], lang))
                    Text(L10n.t("priv.p3", [:], lang))
                }
                .padding(.vertical, 6)
            }
            Section(L10n.t("priv.share", [:], lang)) {
                Label(L10n.t("set.sharingSoon", [:], lang), systemImage: "person.2.badge.gearshape")
                    .foregroundStyle(.secondary)
            }
            Section {
                Link(destination: URL(string: "https://github.com/jakubsejkora/bezpecne-qr/blob/main/PRIVACY.md")!) {
                    Label(L10n.t("priv.policy", [:], lang), systemImage: "doc.text")
                }
            }
        }
        .navigationTitle(L10n.t("priv.title", [:], lang))
    }
}

/// How to block third-party payments at Czech operators (shared/content/operator-guide.json).
struct OperatorGuideScreen: View {
    private let guide = RuleSet.bundled.operatorGuide
    private let lang = Language.preferred

    var body: some View {
        List {
            Section {
                Text(guide.intro.resolve(lang)).padding(.vertical, 4)
            }
            Section {
                ForEach(Array(guide.operators.enumerated()), id: \.offset) { _, op in
                    DisclosureGroup {
                        ForEach(Array((op.steps[lang.rawValue] ?? op.steps["cs"] ?? []).enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1).").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                                Text(step)
                            }
                            .padding(.vertical, 2)
                        }
                    } label: {
                        HStack {
                            Text(op.name.resolve(lang)).font(.headline)
                            if op.verified == false {
                                Text(L10n.t("op.unverified", [:], lang))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                            }
                        }
                    }
                }
            }
            Section(L10n.t("op.tips", [:], lang)) {
                ForEach(guide.tips[lang.rawValue] ?? guide.tips["cs"] ?? [], id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb").labelStyle(.titleAndIcon)
                }
            }
        }
        .navigationTitle(L10n.t("op.title", [:], lang))
    }
}

/// "Už jsem zadal(a) údaje" — what to do after entering details on a scam page.
struct RecoveryGuideScreen: View {
    private let guide = RuleSet.bundled.recoveryGuide
    private let lang = Language.preferred

    var body: some View {
        List {
            Section {
                Text(guide.intro.resolve(lang)).padding(.vertical, 4)
            }
            Section {
                ForEach(Array(guide.sections.enumerated()), id: \.offset) { _, section in
                    DisclosureGroup(section.title.resolve(lang)) {
                        ForEach(Array((section.steps[lang.rawValue] ?? section.steps["cs"] ?? []).enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1).").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                                Text(step)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            Section {
                ForEach(guide.contacts[lang.rawValue] ?? guide.contacts["cs"] ?? [], id: \.self) { contact in
                    Label(contact, systemImage: "phone.circle")
                }
            }
        }
        .navigationTitle(guide.title.resolve(lang))
    }
}

struct AboutScreen: View {
    private let lang = Language.preferred

    var body: some View {
        List {
            Section {
                Text(L10n.t("about.text", [:], lang)).padding(.vertical, 4)
            }
            Section {
                LabeledContent(L10n.t("set.version", [:], lang), value: AppInfo.version)
                Link(destination: URL(string: "https://github.com/jakubsejkora/bezpecne-qr/blob/main/CHANGELOG.md")!) {
                    Label(L10n.t("set.changelog", [:], lang), systemImage: "sparkles")
                }
                Link(destination: URL(string: "https://github.com/jakubsejkora/bezpecne-qr")!) {
                    Label(L10n.t("set.source", [:], lang), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "mailto:jakub@sejkora.cz?subject=Bezpe%C4%8Dn%C3%A9%20QR")!) {
                    LabeledContent {
                        Text("jakub@sejkora.cz")
                    } label: {
                        Label(L10n.t("set.coop", [:], lang), systemImage: "envelope")
                    }
                }
                LabeledContent(L10n.t("set.license", [:], lang), value: L10n.t("set.licenseVal", [:], lang))
            }
        }
        .navigationTitle(L10n.t("about.title", [:], lang))
    }
}
