import BQCore
import BQUI
import Contacts
import ContactsUI
import CoreImage.CIFilterBuiltins
import EventKit
import EventKitUI
import MessageUI
import NetworkExtension
import Photos
import SafariServices
import UIKit

/// Performs what the user chose on the result sheet. Every hand-off to another app or system
/// service happens here (BQUI itself has no side effects).
@MainActor
final class ActionHandler: NSObject, ResultActionHandler {
    /// Called when the user wants to go back to scanning (closes the sheet).
    var onClose: (() -> Void)?
    /// Called for a one-shot manual inspection of a skipped link.
    var onManualCheck: (() -> Void)?

    private var completion: CheckedContinuation<ActionResult, Never>?

    func perform(_ action: ResultAction, for analysis: Analysis) async -> ActionResult {
        let lang = Language.preferred
        switch action {
        case .open(let url):
            // Store and messenger links belong to their apps (universal links), everything else
            // opens in the in-app browser.
            if analysis.type == .store || analysis.type == .messenger {
                let opened = await UIApplication.shared.open(url)
                return opened ? .done(toast: nil) : await open(url)
            }
            return await open(url)
        case .manualCheck:
            onManualCheck?()
            return .done(toast: nil)
        case .copy(let text, let kind):
            copy(text, sensitive: kind == .password)
            return .done(toast: L10n.t("toast.copied", [:], lang))
        case .call(let number):
            guard let url = URL(string: "tel:" + number.filter { !$0.isWhitespace }.replacingOccurrences(of: "#", with: "%23")) else { return .failed(L10n.t("error.generic", [:], lang)) }
            return await open(url)
        case .sms(let number, let body):
            return await composeSMS(number: number, body: body)
        case .mail(let url):
            return await open(url)
        case .addContact:
            return await addContact(analysis)
        case .addEvent:
            return await addEvent(analysis)
        case .joinWiFi:
            return await joinWiFi(analysis)
        case .openMaps(let latitude, let longitude, let label):
            var c = URLComponents(string: "maps://")!
            c.queryItems = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"), URLQueryItem(name: "q", value: label ?? "\(latitude),\(longitude)")]
            return await open(c.url!)
        case .saveQRImage:
            return await saveQR(analysis.code.text)
        case .openInPasswords:
            guard let url = URL(string: analysis.code.text) else { return .failed(L10n.t("error.generic", [:], lang)) }
            return await open(url)
        case .backToScanning, .close:
            onClose?()
            return .done(toast: nil)
        }
    }

    // MARK: Presenting

    private var topController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: Links

    private func open(_ url: URL) async -> ActionResult {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            guard let top = topController else { return .failed(L10n.t("error.generic", [:], .preferred)) }
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = false
            let safari = SFSafariViewController(url: url, configuration: configuration)
            safari.dismissButtonStyle = .close
            top.present(safari, animated: true)
            return .done(toast: nil)
        }
        let opened = await UIApplication.shared.open(url)
        return opened ? .done(toast: nil) : .failed(L10n.t("error.noApp", [:], .preferred))
    }

    // MARK: Clipboard

    private func copy(_ text: String, sensitive: Bool) {
        if sensitive {
            // Passwords stay on this device and expire from the clipboard after two minutes.
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]],
                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        } else {
            UIPasteboard.general.string = text
        }
    }

    // MARK: Messages

    private func composeSMS(number: String, body: String) async -> ActionResult {
        guard MFMessageComposeViewController.canSendText(), let top = topController else {
            var c = URLComponents()
            c.scheme = "sms"
            c.path = number
            if !body.isEmpty { c.queryItems = [URLQueryItem(name: "body", value: body)] }
            guard let url = c.url else { return .failed(L10n.t("error.generic", [:], .preferred)) }
            return await open(url)
        }
        let composer = MFMessageComposeViewController()
        composer.recipients = [number]
        composer.body = body
        composer.messageComposeDelegate = self
        return await withCheckedContinuation { continuation in
            completion = continuation
            top.present(composer, animated: true)
        }
    }

    // MARK: Contacts

    private func addContact(_ analysis: Analysis) async -> ActionResult {
        guard case .contact(let info) = analysis.content, let top = topController else { return .failed(L10n.t("error.generic", [:], .preferred)) }
        let contact = CNMutableContact()
        let parts = info.name.split(separator: " ")
        if parts.count >= 2 {
            contact.givenName = parts.dropLast().joined(separator: " ")
            contact.familyName = String(parts.last!)
        } else {
            contact.givenName = info.name
        }
        contact.organizationName = info.org ?? ""
        contact.jobTitle = info.title ?? ""
        contact.phoneNumbers = info.tels.map { CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0)) }
        contact.emailAddresses = info.emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
        // A URL that raised a warning is not copied into the address book.
        contact.urlAddresses = info.urls.filter { $0 != info.flaggedUrl }.map { CNLabeledValue(label: CNLabelURLAddressHomePage, value: $0 as NSString) }
        if let note = info.note { contact.note = note }
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = self
        let navigation = UINavigationController(rootViewController: controller)
        return await withCheckedContinuation { continuation in
            completion = continuation
            top.present(navigation, animated: true)
        }
    }

    // MARK: Calendar

    private func addEvent(_ analysis: Analysis) async -> ActionResult {
        guard case .event(let info) = analysis.content, let top = topController else { return .failed(L10n.t("error.generic", [:], .preferred)) }
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = info.summary
        event.location = info.location
        event.notes = info.description
        if let start = Format.parseISODate(info.start) {
            event.startDate = start
            event.endDate = Format.parseISODate(info.end) ?? start.addingTimeInterval(3600)
            event.isAllDay = (info.start?.count ?? 0) == 10
        }
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = self
        return await withCheckedContinuation { continuation in
            completion = continuation
            top.present(controller, animated: true)
        }
    }

    // MARK: Wi‑Fi

    private func joinWiFi(_ analysis: Analysis) async -> ActionResult {
        guard case .wifi(let info) = analysis.content else { return .failed(L10n.t("error.generic", [:], .preferred)) }
        let configuration: NEHotspotConfiguration
        switch info.security {
        case "open":
            configuration = NEHotspotConfiguration(ssid: info.ssid)
        case "WEP":
            configuration = NEHotspotConfiguration(ssid: info.ssid, passphrase: info.password ?? "", isWEP: true)
        default:
            configuration = NEHotspotConfiguration(ssid: info.ssid, passphrase: info.password ?? "", isWEP: false)
        }
        configuration.hidden = info.hidden
        configuration.joinOnce = false
        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
            return .done(toast: L10n.t("toast.joined", ["ssid": info.ssid], .preferred))
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain
            && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
            return .done(toast: L10n.t("toast.joined", ["ssid": info.ssid], .preferred))
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain
            && error.code == NEHotspotConfigurationError.userDenied.rawValue {
            return .cancelled
        } catch {
            return .failed(L10n.t("error.wifi", [:], .preferred))
        }
    }

    // MARK: Photos

    private func saveQR(_ payload: String) async -> ActionResult {
        guard let image = ActionHandler.qrImage(payload) else { return .failed(L10n.t("error.generic", [:], .preferred)) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .failed(L10n.t("error.photos", [:], .preferred)) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .done(toast: L10n.t("toast.savedPhotos", [:], .preferred))
        } catch {
            return .failed(L10n.t("error.photos", [:], .preferred))
        }
    }

    /// Renders a payment code as a clean, high-contrast QR image that banking apps can import.
    static func qrImage(_ payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let padded = scaled.composited(over: CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -48, dy: -48)))
        guard let cg = CIContext().createCGImage(padded, from: padded.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func finish(_ result: ActionResult) {
        completion?.resume(returning: result)
        completion = nil
    }
}

extension ActionHandler: MFMessageComposeViewControllerDelegate {
    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            finish(result == .sent ? .done(toast: nil) : .cancelled)
        }
    }
}

extension ActionHandler: CNContactViewControllerDelegate {
    nonisolated func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        let saved = contact != nil
        MainActor.assumeIsolated {
            viewController.dismiss(animated: true)
            finish(saved ? .done(toast: L10n.t("act.contactSaved", [:], .preferred)) : .cancelled)
        }
    }
}

extension ActionHandler: EKEventEditViewDelegate {
    nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            finish(action == .saved ? .done(toast: L10n.t("toast.event", [:], .preferred)) : .cancelled)
        }
    }
}
