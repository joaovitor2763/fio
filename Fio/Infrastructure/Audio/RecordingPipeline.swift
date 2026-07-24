import AVFoundation
import Speech

struct FinishedRecording {
    let transcript: String
    let duration: TimeInterval
    let audioFileName: String?
}

enum RecordingSetupError: LocalizedError {
    case microphoneFormatUnavailable
    case transcriptionFormatUnavailable
    case languageUnavailable(String)
    case audioPipelineUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneFormatUnavailable:
            "The microphone is not providing a usable audio format."
        case .transcriptionFormatUnavailable:
            "Transcription is not available for this language yet."
        case .languageUnavailable(let language):
            "\(language) transcription is not available on this device."
        case .audioPipelineUnavailable:
            "The microphone format could not be converted."
        }
    }
}

/// Runs on the audio render thread: converts microphone buffers to the
/// analyzer's format, yields them to the analyzer, and reports levels.
/// Confined to the single tap callback queue, hence @unchecked Sendable.
final class MicrophonePipeline: @unchecked Sendable {
    /// The converter invokes its input block synchronously during `convert`.
    /// A reference box makes that single-call state explicit to Swift 6.
    private final class ConversionInputState: @unchecked Sendable {
        var served = false
    }

    /// AVAudioConverter consumes this buffer synchronously inside `convert`.
    private final class InputBufferBox: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }
    }

    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let audioWriter: AudioRecordingWriter
    private let onLevel: @Sendable (Float) -> Void

    init?(
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat,
        into continuation: AsyncStream<AnalyzerInput>.Continuation,
        audioWriter: AudioRecordingWriter,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        self.outputFormat = outputFormat
        self.continuation = continuation
        self.audioWriter = audioWriter
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
        audioWriter.write(buffer)
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let inputState = ConversionInputState()
        let inputBuffer = InputBufferBox(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if inputState.served {
                statusPointer.pointee = .noDataNow
                return nil
            }
            inputState.served = true
            statusPointer.pointee = .haveData
            return inputBuffer.buffer
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

/// Writes AAC incrementally as microphone buffers arrive, so long recordings
/// stay compact and never need to be held in memory.
final class AudioRecordingWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private var writtenFrames: AVAudioFramePosition = 0
    private var writeFailed = false

    init(url: URL, inputFormat: AVAudioFormat) throws {
        let channelCount = max(1, Int(inputFormat.channelCount))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: 64_000 * min(channelCount, 2),
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
    }

    var hasUsableAudio: Bool {
        writtenFrames > 0 && !writeFailed
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard !writeFailed else { return }
        do {
            try file.write(from: buffer)
            writtenFrames += AVAudioFramePosition(buffer.frameLength)
        } catch {
            writeFailed = true
        }
    }

    func close() {
        file.close()
    }
}
