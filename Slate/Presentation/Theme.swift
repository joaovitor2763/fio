import SwiftUI

/// Slate's palette: black, white, and the grays between them.
enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.10)
    static let cardStroke = Color(white: 0.17)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.56)
    static let tertiaryText = Color(white: 0.38)
}

/// Card press feedback: a slight settle instead of an opacity flash.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Where a tap on the timeline can lead.
enum Route: Hashable {
    case entry(UUID)
    case review(UUID)
    case reviewList
}
