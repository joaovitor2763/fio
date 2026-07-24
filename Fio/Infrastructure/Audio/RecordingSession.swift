import AVFoundation
import Speech
import Observation
import FioKit

/// Captures the microphone, stores a compact M4A, and streams the same audio
/// into SpeechAnalyzer. Both the audio and transcript stay on this device.
@MainActor
@Observable
final class RecordingSession {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case paused
        case finishing
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var transcriptionLanguageName = "Preparing language…"
    /// Rolling microphone levels driving the waveform, newest last.
    private(set) var levels: [Float] = Array(repeating: 0, count: RecordingSession.barCount)

    static let barCount = 44

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var pipeline: MicrophonePipeline?
    private var resultsTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var isTapInstalled = false
    private var audioFileURL: URL?
    private var audioWriter: AudioRecordingWriter?

    private var finalizedTranscript = ""
    private var volatileTranscript = ""

    var transcript: String {
        (finalizedTranscript + volatileTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts the potentially slow model check while the timeline is visible,
    /// so tapping the microphone usually only has to start the audio engine.
    static func preloadTranscriptionAssets() async {
        await TranscriptionAssetPreloader.shared.preload()
    }

    func start() async {
        guard phase == .idle else { return }
#if DEBUG
        if ProcessInfo.processInfo.environment["FIO_UI_TESTING"] == "1" {
            transcriptionLanguageName = "On-device transcription"
            phase = .recording
            return
        }
#endif
        phase = .preparing
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                phase = .failed("Fio needs the microphone to hear you. You can allow it in Settings.")
                return
            }

            guard let transcriptionLocale = await TranscriptionLanguagePreference.resolvedLocale() else {
                throw RecordingSetupError.languageUnavailable(
                    TranscriptionLanguagePreference.selectedDisplayName
                )
            }
            transcriptionLanguageName = TranscriptionLanguagePreference.displayName(
                for: transcriptionLocale
            )

            try await TranscriptionAssetPreloader.shared.ensureAssets(
                for: transcriptionLocale
            )

            let transcriber = SpeechTranscriber(
                locale: transcriptionLocale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            self.transcriber = transcriber

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            // `.spokenAudio` is paired with `.playAndRecord` by Apple's
            // SpeechAnalyzer capture pipeline. Using it with `.record`
            // causes AVAudioSession to reject the configuration (OSStatus -50).
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let micFormat = engine.inputNode.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                throw RecordingSetupError.microphoneFormatUnavailable
            }

            let audioFileURL = try AudioFileStore.makeRecordingURL()
            self.audioFileURL = audioFileURL
            let audioWriter = try AudioRecordingWriter(
                url: audioFileURL,
                inputFormat: micFormat
            )
            self.audioWriter = audioWriter

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: micFormat
            ) else {
                throw RecordingSetupError.transcriptionFormatUnavailable
            }

            let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
            inputBuilder = builder
            try await analyzer.start(inputSequence: inputSequence)

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        self?.take(text: text, isFinal: result.isFinal)
                    }
                } catch {
                    // The stream ends when the analyzer finishes; errors here
                    // just mean we keep whatever was already transcribed.
                }
            }

            guard let pipeline = MicrophonePipeline(
                from: micFormat,
                to: analyzerFormat,
                into: builder,
                audioWriter: audioWriter,
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.push(level: level) }
                }
            ) else {
                throw RecordingSetupError.audioPipelineUnavailable
            }
            self.pipeline = pipeline

            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { @Sendable buffer, _ in
                pipeline.consume(buffer)
            }
            isTapInstalled = true
            engine.prepare()
            try engine.start()
            phase = .recording
            startTicker()
        } catch {
            await abandonStart()
            phase = .failed("Recording could not start. \(error.localizedDescription)")
        }
    }

    func pause() {
        guard phase == .recording else { return }
        engine.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        do {
            try engine.start()
            phase = .recording
        } catch {
            phase = .failed("Recording could not resume. \(error.localizedDescription)")
        }
    }

    /// Stops the tap, finalizes the analyzer and M4A, and returns both results.
    func finish() async -> FinishedRecording {
        guard phase == .recording || phase == .paused else {
            return FinishedRecording(
                transcript: transcript,
                duration: elapsed,
                audioFileName: nil
            )
        }
        phase = .finishing
        stopEngine()
        audioWriter?.close()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let fileName: String?
        if audioWriter?.hasUsableAudio == true {
            fileName = audioFileURL?.lastPathComponent
        } else {
            AudioFileStore.deleteFile(at: audioFileURL)
            fileName = nil
        }

        phase = .done
        return FinishedRecording(
            transcript: transcript,
            duration: elapsed,
            audioFileName: fileName
        )
    }

    func cancel() {
        stopEngine()
        audioWriter?.close()
        AudioFileStore.deleteFile(at: audioFileURL)
        inputBuilder?.finish()
        resultsTask?.cancel()
        Task { await analyzer?.cancelAndFinishNow() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .done
    }

    // MARK: - Private

    private func stopEngine() {
        ticker?.cancel()
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
    }

    private func abandonStart() async {
        stopEngine()
        inputBuilder?.finish()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        analyzer = nil
        transcriber = nil
        inputBuilder = nil
        pipeline = nil
        resultsTask = nil
        audioWriter?.close()
        audioWriter = nil
        AudioFileStore.deleteFile(at: audioFileURL)
        audioFileURL = nil
    }

    private func take(text: String, isFinal: Bool) {
        if isFinal {
            finalizedTranscript += text
            volatileTranscript = ""
        } else {
            volatileTranscript = text
        }
    }

    private func push(level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(min(1, level * 6))
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if self.phase == .recording {
                    self.elapsed += 0.1
                }
            }
        }
    }

}
