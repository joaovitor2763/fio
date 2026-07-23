import AVFoundation
import Observation

/// Small, file-backed player suitable for long recordings. It never loads the
/// complete audio into memory and exposes seeking, skipping, and playback rate.
@MainActor
@Observable
final class AudioPlaybackController {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    private(set) var rate: Float = 1

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func load(fileName: String) {
        stop()
        errorMessage = nil

        guard let url = AudioFileStore.url(for: fileName) else {
            errorMessage = "The original audio file is no longer available."
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            errorMessage = "The original audio could not be opened."
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
            return
        }

        if currentTime >= duration - 0.05 {
            player.currentTime = 0
            currentTime = 0
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            player.rate = rate
            player.play()
            isPlaying = true
            startTicker()
        } catch {
            errorMessage = "Audio playback could not start."
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let bounded = min(max(0, time), duration)
        player.currentTime = bounded
        currentTime = bounded
    }

    func skip(by interval: TimeInterval) {
        seek(to: currentTime + interval)
    }

    func cycleRate() {
        let rates: [Float] = [1, 1.25, 1.5, 2]
        let index = rates.firstIndex(of: rate) ?? 0
        rate = rates[(index + 1) % rates.count]
        player?.rate = rate
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.currentTime = self.duration
                    self.isPlaying = false
                    return
                }
            }
        }
    }
}
