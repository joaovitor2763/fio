import SwiftUI
import FioKit

extension EntryDetailScreen {
    func exportMenu(for entry: Entry) -> some View {
        Menu {
            if !entry.transcript.isEmpty {
                Button {
                    exportPayload = ExportPayload(items: [entry.transcript.text])
                } label: {
                    Label("Export text", systemImage: "doc.plaintext")
                }
            }

            if let audioURL = entry.audioFileName.flatMap(AudioFileStore.url(for:)) {
                Button {
                    exportPayload = ExportPayload(items: [audioURL])
                } label: {
                    Label("Export audio", systemImage: "waveform")
                }

                if !entry.transcript.isEmpty {
                    Button {
                        exportPayload = ExportPayload(
                            items: [entry.transcript.text, audioURL]
                        )
                    } label: {
                        Label("Export text and audio", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    var audioPlayerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    audioPlayer.cycleRate()
                } label: {
                    Text(playbackRateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Capsule().fill(Theme.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed \(playbackRateLabel)")
            }

            if let message = audioPlayer.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack(spacing: 14) {
                    Button {
                        audioPlayer.togglePlayback()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primaryControlForeground)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.primaryControlBackground))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        audioPlayer.isPlaying
                            ? appLocalized("Pause audio", locale: locale)
                            : appLocalized("Play audio", locale: locale)
                    )

                    VStack(spacing: 6) {
                        AudioScrubber(
                            progress: audioProgress,
                            onSeek: { progress in
                                audioPlayer.seek(to: progress * audioPlayer.duration)
                            }
                        )
                        .disabled(audioPlayer.duration <= 0)

                        HStack {
                            Text(Formatting.clock(audioPlayer.currentTime))
                            Spacer()
                            Text(Formatting.clock(audioPlayer.duration))
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    func retranscriptionAction(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                retranscribe(entry)
            } label: {
                HStack(spacing: 7) {
                    if isRetranscribing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.secondaryText)
                    } else {
                        Image(systemName: "captions.bubble")
                    }
                    if isRetranscribing {
                        Text("Transcribing audio…")
                    } else {
                        Text("Transcribe again")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)

            Button {
                showRetranscriptionLanguages = true
            } label: {
                Label {
                    Text("Transcribe again in another language")
                } icon: {
                    Image(systemName: "globe")
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .disabled(isRetranscribing || entry.audioFileName == nil)
    }

    func retranscribe(_ entry: Entry, using locale: Locale? = nil) {
        showRetranscriptionLanguages = false
        guard !isRetranscribing else { return }
        isRetranscribing = true
        updateError = nil

        Task {
            do {
                let targetLocale: Locale
                if let locale {
                    targetLocale = locale
                } else if let preferredLocale =
                    await TranscriptionLanguagePreference.resolvedLocale() {
                    targetLocale = preferredLocale
                } else {
                    throw RecordingSetupError.languageUnavailable(
                        TranscriptionLanguagePreference.selectedDisplayName
                    )
                }
                try await store.retranscribe(
                    entryID: entry.id,
                    locale: targetLocale
                )
            } catch {
                updateError = error.localizedDescription
            }
            isRetranscribing = false
        }
    }

    func regenerateReflection(for entry: Entry, style: ReflectionStyle) {
        withAnimation(reduceMotion ? nil : Motion.quick) {
            showReflectionRefreshSuggestion = false
        }
        Task {
            await store.regenerateReflection(entryID: entry.id, style: style)
        }
    }

    var audioProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(max(audioPlayer.currentTime / audioPlayer.duration, 0), 1)
    }

    var playbackRateLabel: String {
        audioPlayer.rate == 1
            ? "1×"
            : "\(String(format: "%g", audioPlayer.rate))×"
    }

}
