import Foundation
import Speech

/// A local preference only. SpeechTranscriber requires one locale up front,
/// so "automatic" means the first iPhone-preferred locale the device supports.
enum TranscriptionLanguagePreference {
    static let storageKey = "transcriptionLanguageIdentifier"
    static let automaticSelection = "automatic"
    static let defaultSelection = "pt-BR"

    static var selection: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultSelection
    }

    static func resolvedLocale() async -> Locale? {
        let candidates: [Locale]
        if selection == automaticSelection {
            candidates = Locale.preferredLocales + [Locale.current]
        } else {
            candidates = [Locale(identifier: selection)]
        }

        for candidate in candidates {
            if let supported = await SpeechTranscriber.supportedLocale(
                equivalentTo: candidate
            ) {
                return supported
            }
        }
        return nil
    }

    static func availableLocales() async -> [Locale] {
        let locales = await SpeechTranscriber.supportedLocales
        var seen: Set<String> = []
        return locales
            .filter { seen.insert(identifier(for: $0)).inserted }
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    static func identifier(for locale: Locale) -> String {
        locale.identifier(.bcp47)
    }

    static func displayName(for locale: Locale) -> String {
        let identifier = identifier(for: locale)
        return Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }

    static var selectedDisplayName: String {
        if selection == automaticSelection {
            return "Automatic (iPhone)"
        }
        return displayName(for: Locale(identifier: selection))
    }
}
