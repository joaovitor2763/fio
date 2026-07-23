import AVFoundation
import Foundation
import Speech

/// Reprocesses a preserved recording with a user-selected on-device language.
enum AudioRetranscriptionService {
    static func transcribe(fileName: String, locale: Locale) async throws -> String {
        guard let url = AudioFileStore.url(for: fileName) else {
            throw RetranscriptionError.audioUnavailable
        }

        let file = try AVAudioFile(forReading: url)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }

        async let collectedText = transcriber.results.reduce(into: "") { text, result in
            text += String(result.text.characters)
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let rawTranscript: String = try await collectedText
        let transcript = rawTranscript.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )
        guard !transcript.isEmpty else {
            throw RetranscriptionError.noSpeechRecognized
        }
        return transcript
    }
}

private enum RetranscriptionError: LocalizedError {
    case audioUnavailable
    case noSpeechRecognized

    var errorDescription: String? {
        switch self {
        case .audioUnavailable:
            "The original audio is no longer available."
        case .noSpeechRecognized:
            "No speech was recognized in this audio with that language."
        }
    }
}
