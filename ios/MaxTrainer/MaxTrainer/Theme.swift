import SwiftUI
import UIKit

/// MaxTrainer's look, shared with the dashboard: Space Grotesk for the wordmark, headings, labels and big numbers,
/// Inter for reading text, and the orange gradient. If the font files are missing, the system font is used instead.
enum Brand {
    /// The dashboard's gradient: 135 degrees, #ffc155, then #ff8a3d at 55 percent, then #ff5f4a.
    static let gradient = LinearGradient(
        stops: [.init(color: Color(red: 1.000, green: 0.757, blue: 0.333), location: 0),
                .init(color: Color(red: 1.000, green: 0.541, blue: 0.239), location: 0.55),
                .init(color: Color(red: 1.000, green: 0.373, blue: 0.290), location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func displayName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "SpaceGrotesk-Bold"
        case .semibold: return "SpaceGrotesk-SemiBold"
        default: return "SpaceGrotesk-Medium"
        }
    }

    static func bodyName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }

    /// The size of a system text style at the default text size.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    /// Headings and small bold labels use Space Grotesk, like the dashboard. Everything else reads in Inter.
    static func usesDisplay(_ style: Font.TextStyle, _ weight: Font.Weight) -> Bool {
        switch style {
        case .largeTitle, .title, .title2, .title3, .headline: return true
        case .caption, .caption2: return weight == .bold || weight == .heavy || weight == .black
        default: return false
        }
    }

    /// Navigation titles in the display face.
    @MainActor static func applyAppearance() {
        var large: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        var small: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        if let f = UIFont(name: "SpaceGrotesk-Bold", size: 34) { large[.font] = f }
        if let f = UIFont(name: "SpaceGrotesk-Bold", size: 17) { small[.font] = f }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = large
        bar.titleTextAttributes = small
    }
}

extension Font {
    /// The app's typeface at a system text style's size. It still follows the user's text size setting.
    static func brand(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        let name = Brand.usesDisplay(style, weight) ? Brand.displayName(weight) : Brand.bodyName(weight)
        return .custom(name, size: Brand.size(style), relativeTo: style)
    }

    /// The display face at a fixed size: clocks, big labels and the wordmark.
    static func brand(size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom(Brand.displayName(weight), size: size)
    }
}

/// The MaxTrainer logo: the gradient wordmark from the dashboard.
struct Wordmark: View {
    var size: CGFloat = 24

    var body: some View {
        Text("MaxTrainer")
            .font(.brand(size: size, .bold))
            .tracking(-size * 0.03)
            .foregroundStyle(Brand.gradient)
            .fixedSize()
            .accessibilityLabel("MaxTrainer")
    }
}
