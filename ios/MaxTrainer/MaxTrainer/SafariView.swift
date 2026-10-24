import SwiftUI
import SafariServices

/// An in-app browser sheet, so demo videos never leave MaxTrainer.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Color.accent)
        vc.preferredBarTintColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
