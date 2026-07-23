import AVFoundation
import Speech
import Observation

/// Captures the microphone and streams it into SpeechAnalyzer.
/// Everything happens on this device; nothing is written to disk but the transcript.
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
    /// Rolling microphone levels driving the waveform, newest last.
    private(set) var levels: [Float] = Array(repeating: 0, count: RecordingSession.barCount)
    /// Soft cap on a single entry; "Add 30 seconds" extends it.
    private(set) var timeLimit: TimeInterval = 180

    static let barCount = 44

    var remaining: TimeInterval { max(0, timeLimit - elapsed) }

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var pipeline: MicrophonePipeline?
    private var resultsTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    private var finalizedTranscript = ""
    private var volatileTranscript = ""

    var transcript: String {
        (finalizedTranscript + volatileTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() async {
        guard phase == .idle else { return }
        phase = .preparing
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                phase = .failed("Slate needs the microphone to hear you. You can allow it in Settings.")
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .spokenAudio)
            try audioSession.setActive(true)

            let transcriber = SpeechTranscriber(
                locale: await Self.bestLocale(),
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            self.transcriber = transcriber

            // First launch may need the on-device model assets; still no server —
            // the model is downloaded once by the system, then everything is local.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                phase = .failed("Transcription is not available for this language yet.")
                return
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

            let micFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let pipeline = MicrophonePipeline(
                from: micFormat,
                to: analyzerFormat,
                into: builder,
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.push(level: level) }
                }
            ) else {
                phase = .failed("The microphone format could not be converted.")
                return
            }
            self.pipeline = pipeline

            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
                pipeline.consume(buffer)
            }
            engine.prepare()
            try engine.start()
            phase = .recording
            startTicker()
        } catch {
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

    func addThirtySeconds() {
        timeLimit += 30
    }

    /// Stops the tap, lets the analyzer finalize, and returns the full transcript.
    func finish() async -> String {
        guard phase == .recording || phase == .paused else { return transcript }
        phase = .finishing
        stopEngine()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .done
        return transcript
    }

    func cancel() {
        stopEngine()
        inputBuilder?.finish()
        resultsTask?.cancel()
        Task { try? await analyzer?.cancelAndFinishNow() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .done
    }

    // MARK: - Private

    private func stopEngine() {
        ticker?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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

    private static func bestLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if supported.contains(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) {
            return current
        }
        return supported.first ?? Locale(identifier: "en-US")
    }
}

/// Runs on the audio render thread: converts microphone buffers to the
/// analyzer's format, yields them to the analyzer, and reports levels.
/// Confined to the single tap callback queue, hence @unchecked Sendable.
private final class MicrophonePipeline: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let onLevel: @Sendable (Float) -> Void

    init?(
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat,
        into continuation: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        self.outputFormat = outputFormat
        self.continuation = continuation
        self.onLevel = onLevel
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
            converter.primeMethod = .none
            self.converter = converter
        }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        onLevel(Self.rootMeanSquare(of: buffer))
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var served = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if served {
                statusPointer.pointee = .noDataNow
                return nil
            }
            served = true
            statusPointer.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return output
    }

    private static func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            sum += channel[frame] * channel[frame]
        }
        return sqrt(sum / Float(buffer.frameLength))
    }
}
