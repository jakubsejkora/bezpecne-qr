import BQCore
import Foundation
import Observation

/// What the link inspector is doing right now (shown as honest progress, without a denominator).
public enum CheckStep: Sendable, Equatable {
    /// Checking the address (or expanding a short link).
    case address
    /// Public domain checks (Quad9, RDAP).
    case domain
    /// Following redirects; the number seen so far.
    case redirects(Int)
    /// Reading what the page asks for.
    case page
}

/// What a copied value is, so the app can treat secrets differently (e.g. a pasteboard expiry).
public enum CopyKind: String, Sendable, Equatable, CaseIterable {
    /// Domestic account number (`prefix-number/bank`).
    case account
    case iban
    case amount
    /// Variable symbol (VS).
    case variableSymbol
    /// Payment reference (QRR / SCOR / RF).
    case reference
    /// Wi‑Fi password — a secret: never stored, should expire from the pasteboard.
    case password
    /// Crypto wallet address.
    case cryptoAddress
    /// Text of the code (plain text, data:/javascript: content, intent).
    case text
}

/// Everything the result sheet can ask the app to do. BQUI performs no side effects itself.
public enum ResultAction: Sendable, Equatable {
    /// Open in in-app Safari (http/https) or hand to the system (webcal, store, messengers, itms-services…).
    case open(URL)
    /// The user asked for a one-shot inspection of a skipped sign-in link.
    case manualCheck
    case copy(String, CopyKind)
    case call(String)
    case sms(number: String, body: String)
    case mail(URL)
    /// The app builds the contact from `analysis.content`.
    case addContact
    case addEvent
    case joinWiFi
    case openMaps(latitude: Double, longitude: Double, label: String?)
    /// The app renders the QR from `analysis.code.text` and saves it to Photos.
    case saveQRImage
    /// otpauth: hand the code to the system (Passwords app).
    case openInPasswords
    case backToScanning
    /// Close the sheet. Also sent by "Zrušit" on the checking screen (`isChecking` is still true
    /// then): stop all work and drop late results.
    case close
}

/// The outcome of an action. `done(toast:)` shows the toast (e.g. "Zkopírováno"), `failed` shows the
/// message as an error toast, `cancelled` shows nothing.
public enum ActionResult: Sendable {
    case done(toast: String?)
    case failed(String)
    case cancelled
}

/// Implemented by the app (and the share extension) to perform side effects.
@MainActor
public protocol ResultActionHandler: AnyObject {
    func perform(_ action: ResultAction, for analysis: Analysis) async -> ActionResult
}

/// State of one result sheet. The app owns it: it replaces `analysis` when the network inspection
/// finishes and drives `isChecking` / `step` while it runs.
@MainActor
@Observable
public final class ResultModel {
    /// The current analysis. Replace it when the network inspection finishes. Assigning a
    /// different code resets what the user revealed or opened for the previous one.
    public var analysis: Analysis {
        didSet {
            guard analysis.code.text != oldValue.code.text || analysis.code.symbology != oldValue.code.symbology else { return }
            route = .result
            revealPassword = false
            contactSaved = false
            detailsExpanded = false
            contactMoreExpanded = false
            confirmation = nil
        }
    }

    /// True while the network inspection runs. The checking state appears only when this lasts
    /// longer than ~300 ms; a decisive offline danger is shown immediately instead.
    /// Defaults to true when the analysis says the inspection is still pending (`inc.pending`).
    public var isChecking: Bool {
        didSet {
            guard isChecking != oldValue else { return }
            if isChecking {
                stepHistory = []
                if let step { stepHistory = [step] }
            }
        }
    }

    /// The current inspection step (nil before the first one).
    public var step: CheckStep? {
        didSet {
            guard let step, step != oldValue else { return }
            record(step)
        }
    }

    /// Performs the actions. Held weakly.
    @ObservationIgnored public weak var handler: ResultActionHandler?

    /// The code came from the live camera (enables the sticker tip for links and payments).
    public let fromCamera: Bool

    /// The language of the sheet.
    public var language: Language

    public init(analysis: Analysis, fromCamera: Bool, language: Language = .preferred) {
        self.analysis = analysis
        self.fromCamera = fromCamera
        self.language = language
        self.isChecking = analysis.completeness.reason == "inc.pending"
    }

    // MARK: UI state (internal)

    enum Route: Equatable { case result, pageExtract }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var icon: String
        var isError: Bool
    }

    /// A deliberate confirmation (the accessible alternative of hold-to-confirm buttons).
    struct Confirmation: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var message: String?
        var confirmTitle: String
        var action: ResultAction
    }

    var route: Route = .result
    var revealPassword = false
    var contactSaved = false
    var detailsExpanded = false
    var contactMoreExpanded = false
    var toast: Toast?
    var confirmation: Confirmation?
    /// The action currently being performed by the handler.
    private(set) var inFlight: ResultAction?
    /// Incremented after a contact was saved (drives the confetti).
    private(set) var celebration = 0
    /// Steps seen during the current check, in order (the last one is active).
    private(set) var stepHistory: [CheckStep] = []
    /// The verdict last announced to VoiceOver (announce once per verdict).
    var announcedVerdict: String?

    private func record(_ step: CheckStep) {
        if case .redirects = step, let last = stepHistory.last, case .redirects = last {
            stepHistory[stepHistory.count - 1] = step
        } else if !stepHistory.contains(step) {
            stepHistory.append(step)
        }
    }

    // MARK: Actions

    /// Asks the handler to perform `action`, then shows its toast. Only one action runs at a time,
    /// except closing, which always works.
    func perform(_ action: ResultAction) {
        let leaving = action == .close || action == .backToScanning
        guard leaving || inFlight == nil else { return }
        guard let handler else { return }
        if !leaving { inFlight = action }
        let analysis = self.analysis
        Task { @MainActor [weak self] in
            let result = await handler.perform(action, for: analysis)
            guard let self else { return }
            if !leaving { self.inFlight = nil }
            self.finish(action, result)
        }
    }

    func finish(_ action: ResultAction, _ result: ActionResult) {
        switch result {
        case .done(let message):
            if action == .addContact {
                contactSaved = true
                celebration += 1
            }
            if let message, !message.isEmpty {
                toast = Toast(text: message, icon: Self.toastIcon(for: action), isError: false)
            }
        case .failed(let message):
            toast = Toast(text: message.isEmpty ? language.t("error.generic") : message,
                          icon: "exclamationmark.circle", isError: true)
        case .cancelled:
            break
        }
    }

    static func toastIcon(for action: ResultAction) -> String {
        switch action {
        case .copy: "doc.on.doc"
        case .saveQRImage: "square.and.arrow.down"
        case .sms: "message"
        case .call: "phone"
        case .mail: "envelope"
        case .addContact: "person.crop.circle.badge.checkmark"
        case .addEvent: "calendar.badge.plus"
        case .joinWiFi: "wifi"
        case .openMaps: "map"
        case .open, .openInPasswords: "arrow.up.forward.app"
        case .manualCheck: "magnifyingglass"
        case .backToScanning, .close: "checkmark"
        }
    }
}
