import SwiftUI
import FioKit
import UIKit

/// One entry: the observer's notes, original audio, and full transcript.
struct EntryDetailScreen: View {
    let entryID: UUID

    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(JournalStore.self) var store
    @Environment(\.locale) var locale
    @AppStorage("hasSeenWeekNote") var hasSeenWeekNote = false

    @State var showContextEditor = false
    @State var showTranscriptEditor = false
    @State var showReflectionEditor = false
    @State var showDeleteConfirmation = false
    @State var showRecorder = false
    @State var showRetranscriptionLanguages = false
    @State var isRetranscribing = false
    @State var updateError: String?
    @State var transcriptEditorError: String?
    @State var reflectionEditorError: String?
    @State var dreamStatusMessage: String?
    @State var exportPayload: ExportPayload?
    @State var vocabularySuggestion: VocabularySuggestion?
    @State var draftContext = ""
    @State var draftTranscript = ""
    @State var draftHeadline = ""
    @State var draftObservations: [ReflectionObservationDraft] = []
    @State var draftTopicNames: [String] = []
    @State var draftTopicInput = ""
    @State var audioPlayer = AudioPlaybackController()

    private var entry: Entry? { store.entry(withID: entryID) }

    var body: some View {
        Group {
            if let entry {
                content(for: entry)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
        .background(Theme.background)
        .navigationTitle(entry.map { Formatting.entryTitle(for: $0.createdAt) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .task(id: entry?.audioFileName) {
            if let fileName = entry?.audioFileName {
                audioPlayer.load(fileName: fileName)
            } else {
                audioPlayer.stop()
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    private func content(for entry: Entry) -> some View {
        let hasTopicContent = !store.topics(forEntryID: entry.id).isEmpty
            || !store.topicSuggestions(forEntryID: entry.id).isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !entry.displayObservations.isEmpty || hasTopicContent {
                    observationList(for: entry)
                } else if store.annotatingEntryIDs.contains(entry.id) {
                    HStack(spacing: 8) {
                        ReadingDot()
                        Text("Fio is reading this entry.")
                            .font(.footnote)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                } else {
                    emptyReflectionCard(for: entry)
                }

                if !entry.displayObservations.isEmpty {
                    contextRow(for: entry)
                }

                if !hasSeenWeekNote {
                    weekNoteCard
                }

                if entry.audioFileName != nil {
                    audioPlayerCard
                    retranscriptionAction(for: entry)
                }

                transcriptSection(for: entry)

                if !entry.authorContext.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Added later")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                        Text(entry.authorContext)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                footerActions(for: entry)
                    .padding(.top, 12)
            }
            .padding(20)
        }
        .sheet(isPresented: $showContextEditor) { contextEditor(for: entry) }
        .sheet(isPresented: $showTranscriptEditor) { transcriptEditor(for: entry) }
        .sheet(isPresented: $showReflectionEditor) { reflectionEditor(for: entry) }
        .sheet(isPresented: $showRetranscriptionLanguages) {
            RetranscriptionLanguagePicker { locale in
                retranscribe(entry, using: locale)
            }
        }
        .sheet(item: $exportPayload) { payload in
            ActivityShareSheet(items: payload.items)
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen(replacingEntryID: entry.id)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                Task {
                    await store.delete(entryID: entry.id)
                    dismiss()
                }
            }
            .accessibilityIdentifier("confirm-delete-entry-button")
        } message: {
            Text("It is only stored on this phone, so this removes it everywhere it exists.")
        }
        .confirmationDialog(
            "Use this correction next time?",
            isPresented: Binding(
                get: { vocabularySuggestion != nil },
                set: { if !$0 { vocabularySuggestion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let suggestion = vocabularySuggestion {
                Button(
                    "Always replace “\(suggestion.source)” with “\(suggestion.replacement)”"
                ) {
                    PersonalVocabulary.add(suggestion)
                    vocabularySuggestion = nil
                }
            }
            Button("Not now", role: .cancel) {
                vocabularySuggestion = nil
            }
        } message: {
            Text("Fio will apply this on future transcriptions before creating a reflection.")
        }
        .alert(
            "Entry could not be updated",
            isPresented: Binding(
                get: { updateError != nil },
                set: { if !$0 { updateError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateError ?? "")
        }
    }

}
