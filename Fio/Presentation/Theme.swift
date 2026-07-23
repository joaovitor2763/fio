import SwiftUI
import UIKit

/// Fio's adaptive palette, based on the G4 OS Clean light and dark surfaces.
enum Theme {
    static let background = adaptive(light: 0xFFFFFF, dark: 0x090A0B)
    static let card = adaptive(light: 0xF4F6F7, dark: 0x121314)
    static let cardStroke = adaptive(light: 0xDCE2E6, dark: 0x2A2C2E)
    static let primaryText = adaptive(light: 0x001F35, dark: 0xF4F4F3)
    static let secondaryText = adaptive(light: 0x526675, dark: 0x999B9C)
    static let tertiaryText = adaptive(light: 0x7B8B96, dark: 0x686A6B)
    static let accent = adaptive(light: 0xB9915B, dark: 0xC9A84C)
    static let shadow = Color.black
    static let primaryControlBackground = primaryText
    static let primaryControlForeground = background

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Card press feedback: a slight settle instead of an opacity flash.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension View {
    /// Keeps navigation chrome visually absent at the scroll edge, then lets
    /// the system reveal a translucent surface as content moves underneath it.
    func scrollResponsiveNavigationBar() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

/// Where a tap on the timeline can lead.
enum Route: Hashable {
    case entry(UUID)
    case review(UUID)
    case reviewList
    case insights
}
