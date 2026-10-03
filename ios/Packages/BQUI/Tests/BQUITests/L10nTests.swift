import BQCore
import Foundation
import Testing
@testable import BQUI

struct L10nTests {
    @Test func fillsPlaceholders() {
        #expect(L10n.t("check.redirects", ["n": "2"], .cs) == "Sleduji přesměrování — zatím 2")
        #expect(L10n.t("check.redirects", ["n": "2"], .en) == "Following redirects — 2 so far")
        #expect(L10n.t("band.safe", .cs) == "Bez známých hrozeb")
        #expect(L10n.t("a11y.verdictScored", ["score": "72", "band": "nebezpečné"], .cs) == "Riziko 72 ze 100, nebezpečné")
    }

    @Test func unknownPlaceholdersAndKeysPassThrough() {
        #expect(L10n.fill("{a} {b}", ["a": "1"]) == "1 {b}")
        #expect(L10n.t("does.not.exist", .en) == "does.not.exist")
    }

    @Test("Strings the app target relies on exist in both languages", arguments: [
        "error.generic", "error.noApp", "error.wifi", "error.photos", "error.camera", "set.sharingSoon", "set.debug",
        "scan.noCode", "onb.privacyNote", "toast.copied", "toast.savedPhotos",
    ])
    func appKeys(_ key: String) {
        for lang in Language.allCases {
            #expect(L10n.table[lang.rawValue]?[key]?.isEmpty == false, "\(lang).\(key)")
        }
    }

    @Test func prototypeOnlyGroupsAreExcluded() {
        #expect(!L10n.has("ctl.scan"))
        #expect(!L10n.has("catalog.title"))
        #expect(L10n.has("band.danger"))
    }

    @Test("ui-strings.json is up to date with the prototype and the overlay")
    func generatedFileIsFresh() throws {
        // Mirrors `node scripts/gen-ui-strings.mjs --check` for the overlay half (Node isn't available in tests).
        let overlayURL = Corpus.root.appendingPathComponent("ios/Packages/BQUI/Sources/BQUI/Resources/ios-strings.overlay.json")
        let overlay = try JSONSerialization.jsonObject(with: Data(contentsOf: overlayURL)) as? [String: Any]
        for lang in Language.allCases {
            let strings = try #require(overlay?[lang.rawValue] as? [String: String])
            for (key, value) in strings {
                #expect(L10n.table[lang.rawValue]?[key] == value, "\(lang).\(key) differs — run node scripts/gen-ui-strings.mjs")
            }
        }
    }
}
