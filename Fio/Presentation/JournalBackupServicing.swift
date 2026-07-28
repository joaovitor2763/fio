import Foundation

enum RecoveryPhraseFormat {
    static let wordCount = 16
}

@MainActor
protocol JournalBackupServicing {
    func prepareBackup() throws -> PreparedJournalBackup

    func summary(
        for data: Data,
        recoveryPhrase: String
    ) throws -> JournalBackupSummary

    func restore(
        from data: Data,
        recoveryPhrase: String
    ) throws -> JournalBackupSummary
}

struct PreparedJournalBackup: Identifiable {
    let id = UUID()
    let data: Data
    let recoveryPhrase: String
    let fileName: String
    let summary: JournalBackupSummary
}

struct JournalBackupSummary: Equatable {
    let exportedAt: Date
    let entryCount: Int
    let reviewCount: Int
    let topicCount: Int
    let omittedAudioCount: Int
}

extension JournalStore {
    func restoreBackup(
        from data: Data,
        recoveryPhrase: String
    ) async throws -> JournalBackupSummary {
        guard !isDreaming,
              !isComposingReviews,
              annotatingEntryIDs.isEmpty else {
            throw JournalBackupAvailabilityError.journalIsBusy
        }

        let wasLoaded = isLoaded
        isLoaded = false
        do {
            let summary = try backupService.restore(
                from: data,
                recoveryPhrase: recoveryPhrase
            )
            await refresh()
            return summary
        } catch {
            isLoaded = wasLoaded
            throw error
        }
    }
}

private enum JournalBackupAvailabilityError: LocalizedError {
    case journalIsBusy

    var errorDescription: String? {
        String(
            localized: "Wait for Fio to finish its current journal update, then import again."
        )
    }
}
