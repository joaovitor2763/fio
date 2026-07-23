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

/// A small motion vocabulary keeps the interface calm and consistent.
enum Motion {
    static let quick = Animation.easeOut(duration: 0.14)
    static let standard = Animation.smooth(duration: 0.22)
    static let contextual = Animation.spring(duration: 0.30, bounce: 0.06)
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
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

extension View {
    /// Keeps navigation chrome visually absent at the scroll edge, then lets
    /// the system reveal a translucent surface as content moves underneath it.
    func scrollResponsiveNavigationBar() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    /// Expands detail views from their source while respecting Reduce Motion.
    @ViewBuilder
    func contextualNavigationTransition<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID,
        reduceMotion: Bool
    ) -> some View {
        if reduceMotion {
            self
        } else {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}

/// Where a tap on the timeline can lead.
enum Route: Hashable {
    case entry(UUID)
    case review(UUID, source: ReviewRouteSource)
}

enum ReviewRouteSource: Hashable {
    case timeline
    case list
}
