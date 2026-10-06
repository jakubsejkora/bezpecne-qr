import BQCore
import BQUI
import SwiftUI

struct HelpScreen: View {
    @Environment(\.bqDesign) private var design
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DesignHeading(L10n.t("help.headline", .preferred), subtitle: L10n.t("help.intro", .preferred))
                NavigationLink { RecoveryGuideScreen() } label: {
                    helpRow("lifepreserver", L10n.t("set.recovery", .preferred), L10n.t("help.recoverySub", .preferred))
                }
                NavigationLink { OperatorGuideScreen() } label: {
                    helpRow("antenna.radiowaves.left.and.right", L10n.t("set.operator", .preferred), L10n.t("help.operatorSub", .preferred))
                }
                NavigationLink { PrivacyScreen() } label: {
                    helpRow("hand.raised", L10n.t("set.privacy", .preferred), L10n.t("help.privacySub", .preferred))
                }
            }.padding(design.padding)
        }.background(design.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
    private func helpRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: symbol).font(.title2); Spacer(); Image(systemName: "arrow.up.right").font(.body) }
            Text(title).font(.system(.title2, design: design.fontDesign, weight: .bold)).multilineTextAlignment(.leading)
            Text(subtitle).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.leading)
        }.foregroundStyle(design.ink).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(design.surface, in: RoundedRectangle(cornerRadius: design.radius))
    }
}
