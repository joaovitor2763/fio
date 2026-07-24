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

enum DreamScheduleState {
    private static let analyzedThroughKey = "dreamAnalyzedThrough"
    private static let corpusRevisionKey = "dreamCorpusRevision"
    private static let analyzedRevisionKey = "dreamAnalyzedRevision"
    private static let lastSuccessfulRunKey = "dreamLastSuccessfulRun"

    static var currentRevision: Int {
        UserDefaults.standard.integer(forKey: corpusRevisionKey)
    }

    static func needsAnalysis(latestEntryDate: Date) -> Bool {
        guard UserDefaults.standard.object(forKey: analyzedThroughKey) != nil,
              UserDefaults.standard.object(forKey: analyzedRevisionKey) != nil else {
            return true
        }
        return currentRevision
            != UserDefaults.standard.integer(forKey: analyzedRevisionKey)
            || latestEntryDate.timeIntervalSince1970
                > UserDefaults.standard.double(forKey: analyzedThroughKey)
    }

    static func shouldRunAutomatically(
        latestEntryDate: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard needsAnalysis(latestEntryDate: latestEntryDate) else {
            return false
        }
        guard let lastSuccessfulRun = UserDefaults.standard.object(
            forKey: lastSuccessfulRunKey
        ) as? Date else {
            return true
        }
        return !calendar.isDate(lastSuccessfulRun, inSameDayAs: now)
    }

    @discardableResult
    static func markAnalyzed(
        through date: Date,
        ifRevisionIs expectedRevision: Int,
        completedAt: Date = .now
    ) -> Bool {
        guard currentRevision == expectedRevision else { return false }
        UserDefaults.standard.set(
            date.timeIntervalSince1970,
            forKey: analyzedThroughKey
        )
        UserDefaults.standard.set(
            expectedRevision,
            forKey: analyzedRevisionKey
        )
        UserDefaults.standard.set(
            completedAt,
            forKey: lastSuccessfulRunKey
        )
        return true
    }

    static func markNeedsAnalysis() {
        UserDefaults.standard.set(
            currentRevision &+ 1,
            forKey: corpusRevisionKey
        )
    }
}

/// Prevents the one-time conversion from legacy reflection tags from
/// resurrecting topic memberships the author later removes.
enum LegacyTopicMigrationState {
    private static let completionKey = "legacyTagsMigratedToTopics.v1"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completionKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: completionKey)
    }
}

func appLocalized(_ key: String.LocalizationValue, locale: Locale) -> String {
    String(localized: key, locale: locale)
}
