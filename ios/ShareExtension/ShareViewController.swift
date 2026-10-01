import UIKit

/// Stub share extension. It proves that the signed extension embeds and launches;
/// checking codes in shared images arrives with the share-extension milestone.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Bezpečné QR\nKontrola kódů z obrázků bude v další verzi."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true

        let close = UIButton(configuration: .borderedProminent(), primaryAction: UIAction(title: "Zavřít") { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })

        let stack = UIStackView(arrangedSubviews: [label, close])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
