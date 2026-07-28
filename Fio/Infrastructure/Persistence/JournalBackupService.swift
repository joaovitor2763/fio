import CryptoKit
import Foundation
import SwiftData
import FioKit

@MainActor
final class JournalBackupService: JournalBackupServicing {
    private enum Format {
        static let identifier = "com.joaovitorsilva.fio.encrypted-backup"
        static let envelopeVersion = 1
        static let archiveVersion = 1
        static let maximumFileSize = 100 * 1_024 * 1_024
        static let keyInfo = Data("Fio encrypted backup v1".utf8)
    }

    private let context: ModelContext
    private let defaults: UserDefaults

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        self.context = context
        self.defaults = defaults
    }

    func prepareBackup() throws -> PreparedJournalBackup {
        let archive = try makeArchive()
        let phrase = RecoveryPhrase.generate()
        let encryptedData = try encrypt(archive, recoveryPhrase: phrase)
        let summary = summary(for: archive)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HHmm"

        return PreparedJournalBackup(
            data: encryptedData,
            recoveryPhrase: phrase,
            fileName: "Fio-backup-\(formatter.string(from: archive.exportedAt)).fiobackup",
            summary: summary
        )
    }

    func summary(
        for data: Data,
        recoveryPhrase: String
    ) throws -> JournalBackupSummary {
        summary(for: try decrypt(data, recoveryPhrase: recoveryPhrase))
    }

    func restore(
        from data: Data,
        recoveryPhrase: String
    ) throws -> JournalBackupSummary {
        let archive = try decrypt(data, recoveryPhrase: recoveryPhrase)
        try validate(archive)

        let existingEntries = try context.fetch(FetchDescriptor<EntryRecord>())
        let audioFileNames = existingEntries.compactMap(\.audioFileName)
        let existingReviews = try context.fetch(FetchDescriptor<ReviewRecord>())
        let existingTopics = try context.fetch(FetchDescriptor<TopicRecord>())

        do {
            existingEntries.forEach(context.delete)
            existingReviews.forEach(context.delete)
            existingTopics.forEach(context.delete)

            archive.entries
                .map(\.domainValue)
                .map(EntryRecord.init(from:))
                .forEach(context.insert)
            archive.reviews
                .map(\.domainValue)
                .map(ReviewRecord.init(from:))
                .forEach(context.insert)
            archive.topics
                .map(\.domainValue)
                .map(TopicRecord.init(from:))
                .forEach(context.insert)

            try context.save()
        } catch {
            context.rollback()
            throw JournalBackupError.couldNotRestore
        }

        // A restored archive intentionally has no audio. Remove the recordings
        // belonging to the journal that was just replaced so they cannot
        // become inaccessible orphan files.
        audioFileNames.forEach(AudioFileStore.deleteFile(named:))
        apply(archive.settings)
        LegacyTopicMigrationState.markComplete()
        DreamScheduleState.markNeedsAnalysis()

        return summary(for: archive)
    }

    private func makeArchive() throws -> JournalBackupArchive {
        let entries = try context.fetch(
            FetchDescriptor<EntryRecord>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let reviews = try context.fetch(
            FetchDescriptor<ReviewRecord>(sortBy: [SortDescriptor(\.weekStart)])
        )
        let topics = try context.fetch(
            FetchDescriptor<TopicRecord>(sortBy: [SortDescriptor(\.updatedAt)])
        )

        return JournalBackupArchive(
            schemaVersion: Format.archiveVersion,
            exportedAt: .now,
            audioFilesIncluded: false,
            entries: entries.map(BackupEntry.init(record:)),
            reviews: reviews.map(BackupReview.init(record:)),
            topics: topics.map(BackupTopic.init(record:)),
            settings: BackupSettings(
                appearance: defaults.string(forKey: AppAppearance.storageKey)
                    ?? AppAppearance.system.rawValue,
                interfaceLanguage: defaults.string(
                    forKey: InterfaceLanguage.storageKey
                ) ?? InterfaceLanguage.english.rawValue,
                transcriptionLanguage: defaults.string(
                    forKey: TranscriptionLanguagePreference.storageKey
                ) ?? TranscriptionLanguagePreference.defaultSelection,
                observerGuidance: ObserverPreferences.guidance,
                personalVocabulary: PersonalVocabulary.rules,
                hasSeenWeekNote: defaults.bool(forKey: "hasSeenWeekNote")
            )
        )
    }

    private func encrypt(
        _ archive: JournalBackupArchive,
        recoveryPhrase: String
    ) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let plaintext = try encoder.encode(archive)
            let salt = randomData(count: 32)
            let key = key(for: recoveryPhrase, salt: salt)
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw JournalBackupError.couldNotCreate
            }
            let envelope = EncryptedBackupEnvelope(
                format: Format.identifier,
                version: Format.envelopeVersion,
                salt: salt,
                sealedData: combined
            )
            return try encoder.encode(envelope)
        } catch let error as JournalBackupError {
            throw error
        } catch {
            throw JournalBackupError.couldNotCreate
        }
    }

    private func decrypt(
        _ data: Data,
        recoveryPhrase: String
    ) throws -> JournalBackupArchive {
        guard !data.isEmpty, data.count <= Format.maximumFileSize else {
            throw JournalBackupError.invalidFile
        }

        let cleanPhrase = RecoveryPhrase.normalize(recoveryPhrase)
        guard !cleanPhrase.isEmpty else {
            throw JournalBackupError.missingRecoveryPhrase
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let envelope = try decoder.decode(
                EncryptedBackupEnvelope.self,
                from: data
            )
            guard envelope.format == Format.identifier else {
                throw JournalBackupError.invalidFile
            }
            guard envelope.version == Format.envelopeVersion else {
                throw JournalBackupError.unsupportedVersion
            }
            guard envelope.salt.count == 32 else {
                throw JournalBackupError.invalidFile
            }

            let key = key(for: cleanPhrase, salt: envelope.salt)
            let box = try AES.GCM.SealedBox(combined: envelope.sealedData)
            let plaintext = try AES.GCM.open(box, using: key)
            let archive = try decoder.decode(
                JournalBackupArchive.self,
                from: plaintext
            )
            try validate(archive)
            return archive
        } catch let error as JournalBackupError {
            throw error
        } catch {
            throw JournalBackupError.incorrectPhraseOrDamagedFile
        }
    }

    private func validate(_ archive: JournalBackupArchive) throws {
        guard archive.schemaVersion == Format.archiveVersion else {
            throw JournalBackupError.unsupportedVersion
        }
        guard !archive.audioFilesIncluded,
              archive.entries.count <= 500_000,
              archive.reviews.count <= 20_000,
              archive.topics.count <= 20_000,
              archive.settings.personalVocabulary.count
                <= PersonalVocabulary.maximumRuleCount else {
            throw JournalBackupError.invalidFile
        }

        let entryIDs = archive.entries.map(\.id)
        let reviewIDs = archive.reviews.map(\.id)
        let topicIDs = archive.topics.map(\.id)
        guard Set(entryIDs).count == entryIDs.count,
              Set(reviewIDs).count == reviewIDs.count,
              Set(topicIDs).count == topicIDs.count,
              archive.entries.allSatisfy({
                  $0.duration.isFinite && $0.duration >= 0
              }),
              archive.reviews.allSatisfy({
                  $0.dailyMinutes.allSatisfy { $0.isFinite && $0 >= 0 }
              }) else {
            throw JournalBackupError.invalidFile
        }
    }

    private func apply(_ settings: BackupSettings) {
        let appearance = AppAppearance(rawValue: settings.appearance)
            ?? .system
        let language = InterfaceLanguage(
            rawValue: settings.interfaceLanguage
        ) ?? .english
        defaults.set(appearance.rawValue, forKey: AppAppearance.storageKey)
        defaults.set(
            language.rawValue,
            forKey: InterfaceLanguage.storageKey
        )
        defaults.set(
            settings.transcriptionLanguage,
            forKey: TranscriptionLanguagePreference.storageKey
        )
        defaults.set(
            ObserverPreferences.normalizedGuidance(settings.observerGuidance),
            forKey: ObserverPreferences.guidanceStorageKey
        )
        PersonalVocabulary.rules = settings.personalVocabulary
        defaults.set(settings.hasSeenWeekNote, forKey: "hasSeenWeekNote")
    }

    private func summary(
        for archive: JournalBackupArchive
    ) -> JournalBackupSummary {
        JournalBackupSummary(
            exportedAt: archive.exportedAt,
            entryCount: archive.entries.count,
            reviewCount: archive.reviews.count,
            topicCount: archive.topics.count,
            omittedAudioCount: archive.entries.filter(\.hadAudio).count
        )
    }

    private func key(for phrase: String, salt: Data) -> SymmetricKey {
        let material = SymmetricKey(
            data: Data(RecoveryPhrase.normalize(phrase).utf8)
        )
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: salt,
            info: Format.keyInfo,
            outputByteCount: 32
        )
    }

    private func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

private enum RecoveryPhrase {
    private static let words = """
    acorn amber anchor apple apron arrow atlas autumn badge bamboo beach berry
    birch bird bloom blue boat breeze brick brook brush cabin cactus candle
    canyon cedar cherry cloud clover coast coral creek crystal dawn deer dune
    eagle earth ember fern field flame flower forest fox frost garden globe
    grape grass green harbor hazel hill honey horse island ivory jade lake
    leaf lemon light lilac lime lotus maple meadow melon mint moon moss mountain
    ocean olive orange orchid otter palm paper peach pearl pebble pine plum
    pond poppy quartz rain raven reed river robin rose ruby sand seed shell
    silver sky snow sparrow spring star stone storm sun sunset tiger trail
    tulip valley violet wave wheat willow wind winter wolf wood wren yellow
    """
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<RecoveryPhraseFormat.wordCount)
            .map { _ in words.randomElement(using: &generator)! }
            .joined(separator: " ")
    }

    static func normalize(_ phrase: String) -> String {
        phrase
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private enum JournalBackupError: LocalizedError {
    case couldNotCreate
    case invalidFile
    case unsupportedVersion
    case missingRecoveryPhrase
    case incorrectPhraseOrDamagedFile
    case couldNotRestore

    var errorDescription: String? {
        switch self {
        case .couldNotCreate:
            String(localized: "Fio could not create this backup.")
        case .invalidFile:
            String(localized: "This is not a valid Fio backup.")
        case .unsupportedVersion:
            String(localized: "This backup was created by an unsupported version of Fio.")
        case .missingRecoveryPhrase:
            String(localized: "Enter the recovery phrase for this backup.")
        case .incorrectPhraseOrDamagedFile:
            String(localized: "The recovery phrase is incorrect, or the backup is damaged.")
        case .couldNotRestore:
            String(localized: "Fio could not restore this backup. Your current journal was kept.")
        }
    }
}

private struct EncryptedBackupEnvelope: Codable {
    let format: String
    let version: Int
    let salt: Data
    let sealedData: Data
}

private struct JournalBackupArchive: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let audioFilesIncluded: Bool
    let entries: [BackupEntry]
    let reviews: [BackupReview]
    let topics: [BackupTopic]
    let settings: BackupSettings
}

private struct BackupEntry: Codable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let transcript: String
    let hadAudio: Bool
    let headline: String
    let observations: [String]
    let tags: [String]
    let authorContext: String

    init(record: EntryRecord) {
        id = record.id
        createdAt = record.createdAt
        duration = record.duration
        transcript = record.transcript
        hadAudio = record.audioFileName != nil
        headline = record.headline
        observations = record.observations
        tags = record.tags
        authorContext = record.authorContext
    }

    var domainValue: Entry {
        Entry(
            id: id,
            createdAt: createdAt,
            duration: duration,
            transcript: Transcript(transcript),
            audioFileName: nil,
            reflection: Reflection(
                headline: headline,
                observations: observations,
                tags: tags
            ),
            authorContext: authorContext
        )
    }
}

private struct BackupReview: Codable {
    let id: UUID
    let weekStart: Date
    let createdAt: Date
    let title: String
    let summary: String
    let dailyMinutes: [Double]

    init(record: ReviewRecord) {
        id = record.id
        weekStart = record.weekStart
        createdAt = record.createdAt
        title = record.title
        summary = record.summary
        dailyMinutes = record.dailyMinutes
    }

    var domainValue: WeekReview {
        WeekReview(
            id: id,
            weekStart: weekStart,
            createdAt: createdAt,
            title: title,
            summary: summary,
            dailyMinutes: dailyMinutes
        )
    }
}

private struct BackupTopic: Codable {
    let id: UUID
    let name: String
    let status: Topic.Status
    let entryIDs: [UUID]
    let createdAt: Date
    let updatedAt: Date

    init(record: TopicRecord) {
        let topic = record.asDomain
        id = topic.id
        name = topic.name
        status = topic.status
        entryIDs = topic.entryIDs
        createdAt = topic.createdAt
        updatedAt = topic.updatedAt
    }

    var domainValue: Topic {
        Topic(
            id: id,
            name: name,
            status: status,
            entryIDs: entryIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct BackupSettings: Codable {
    let appearance: String
    let interfaceLanguage: String
    let transcriptionLanguage: String
    let observerGuidance: String
    let personalVocabulary: [VocabularyRule]
    let hasSeenWeekNote: Bool
}
