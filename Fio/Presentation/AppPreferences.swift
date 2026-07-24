import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "interfaceLanguage"

    case portugueseBrazil = "pt-BR"
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var title: LocalizedStringKey {
        switch self {
        case .portugueseBrazil: "Portuguese (Brazil)"
        case .english: "English"
        case .spanish: "Spanish"
        }
    }
}

enum ObserverPreferences {
    static let guidanceStorageKey = "observerGuidance"
    static let maximumGuidanceLength = 500

    static var guidance: String {
        let stored = UserDefaults.standard.string(forKey: guidanceStorageKey) ?? ""
        return normalizedGuidance(stored)
    }

    static func normalizedGuidance(_ text: String) -> String {
        String(
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumGuidanceLength)
        )
    }
}

func appLocalized(_ key: String.LocalizationValue, locale: Locale) -> String {
    String(localized: key, locale: locale)
}
