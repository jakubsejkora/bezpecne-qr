import BQCore

/// SF Symbols for the prototype's icon names (prototype/js/icons.js, cards.js TYPE_ICON / CSQ_ICON).
enum Symbol {
    static func type(_ type: CodeType) -> String {
        switch type {
        case .url: "globe"
        case .spd, .epc, .spc, .payBySquare: "banknote"
        case .sid: "doc.text"
        case .crypto: "bitcoinsign.circle"
        case .sms: "message"
        case .tel: "phone"
        case .mailto: "envelope"
        case .contact: "person"
        case .wifi: "wifi"
        case .event, .webcal: "calendar"
        case .geo: "mappin.and.ellipse"
        case .otpauth, .otpauthMigration, .seed: "key"
        case .login: "laptopcomputer.and.iphone"
        case .fido: "person.badge.key"
        case .walletConnect: "link"
        case .appInstall: "arrow.down.app"
        case .store: "bag"
        case .messenger: "bubble.left.and.bubble.right"
        case .dataURI, .jsURI: "chevron.left.forwardslash.chevron.right"
        case .intent: "arrow.up.forward.app"
        case .emvco: "cart"
        case .gs1: "shippingbox"
        case .bcbp: "airplane"
        case .hc1: "cross.case"
        case .text: "doc.plaintext"
        }
    }

    /// Icon of the verdict header when a critical consequence leads (`v-alert`).
    static func consequence(_ id: String) -> String {
        switch id {
        case "csq.call_forwarding": "phone.arrow.right"
        case "csq.premium_call": "phone"
        case "csq.premium_sms": "message"
        case "csq.twofa_secrets", "csq.seed_phrase": "key"
        case "csq.account_access": "laptopcomputer.and.iphone"
        case "csq.wallet_connect": "link"
        case "csq.profile_install": "gearshape.2"
        case "csq.app_install": "arrow.down.app"
        case "csq.subscription_charge": "repeat"
        case "csq.billing_gateway": "antenna.radiowaves.left.and.right"
        case "csq.executable_content": "chevron.left.forwardslash.chevron.right"
        case "csq.invalid_payment": "banknote"
        default: "exclamationmark.triangle"
        }
    }

    static let danger = "xmark.octagon"
    static let caution = "exclamationmark.triangle"
    static let safe = "checkmark.shield"
    static let incomplete = "icloud.slash"
    static let info = "info.circle"
    static let check = "checkmark"
    static let arrow = "arrow.right"
    static let sticker = "hand.point.up.left"
}
