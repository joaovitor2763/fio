import Foundation
import Speech

/// Serializes Speech model checks away from MainActor so a launch-time preload
/// can never delay journal rendering or interaction.
actor TranscriptionAssetPreloader {
    static let shared = TranscriptionAssetPreloader()

    private var preparedLocales: Set<String> = []
    private var preparationTasks: [String: Task<Void, Error>] = [:]

    func preload() async {
        guard let locale = await TranscriptionLanguagePreference.resolvedLocale() else {
            return
        }
        try? await ensureAssets(for: locale)
    }

    func ensureAssets(for locale: Locale) async throws {
        let identifier = TranscriptionLanguagePreference.identifier(for: locale)
        if preparedLocales.contains(identifier) {
            return
        }
        if let existingTask = preparationTasks[identifier] {
            return try await existingTask.value
        }

        let task = Task {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                try await request.downloadAndInstall()
            }
        }
        preparationTasks[identifier] = task

        do {
            try await task.value
            preparedLocales.insert(identifier)
            preparationTasks[identifier] = nil
        } catch {
            preparationTasks[identifier] = nil
            throw error
        }
    }
}
