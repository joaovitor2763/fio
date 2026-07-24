import SwiftUI
import FioKit

extension EntryDetailScreen {
    func observationList(for entry: Entry) -> some View {
        let acceptedTopics = store.topics(forEntryID: entry.id)
        let suggestions = store.topicSuggestions(forEntryID: entry.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reflection")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if store.annotatingEntryIDs.contains(entry.id) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.secondaryText)
                } else {
                    reflectionMenu(for: entry)
                }
            }

            ForEach(entry.displayObservations, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text("•").foregroundStyle(Theme.secondaryText)
                    Text(line)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }

            if entry.displayObservations.isEmpty {
                Button {
                    regenerateReflection(for: entry, style: .standard)
                } label: {
                    Label("Create reflection", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            if !acceptedTopics.isEmpty || !suggestions.isEmpty {
                Divider()
                    .overlay(Theme.cardStroke)
                    .padding(.top, 2)

                Text(suggestions.isEmpty ? "Topics" : "Topics and suggestions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.tertiaryText)

                WrapLayout {
                    ForEach(acceptedTopics) { topic in
                        NavigationLink(value: Route.topic(topic.id)) {
                            TopicPill(name: topic.name)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(suggestions) { topic in
                        NavigationLink(value: Route.topic(topic.id)) {
                            TopicPill(name: topic.name, isSuggested: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Review why Fio connected these entries")
                    }
                }
            }

            dreamConsolidationAction
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }

    func emptyReflectionCard(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reflection")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    openReflectionEditor(for: entry)
                } label: {
                    Label("Add topic", systemImage: "plus")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primaryText)
            }

            if entry.transcript.isSubstantial {
                Button {
                    regenerateReflection(for: entry, style: .standard)
                } label: {
                    Label("Create reflection", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            dreamConsolidationAction
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }

    var dreamConsolidationAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Theme.cardStroke)
                .padding(.top, 2)

            Button {
                dreamStatusMessage = nil
                Task {
                    let didConsolidate = await store.runDreamNow()
                    dreamStatusMessage = appLocalized(
                        didConsolidate
                            ? "Topics consolidated on this iPhone."
                            : "Dream is unavailable right now. Try again later.",
                        locale: locale
                    )
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "moon.stars")
                        .frame(width: 20)

                    Group {
                        if store.isDreaming {
                            Text("Consolidating topics…")
                        } else {
                            Text("Consolidate topics now")
                        }
                    }
                    .font(.footnote.weight(.medium))

                    Spacer()

                    if store.isDreaming {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isDreaming)

            Text(
                dreamStatusMessage
                    ?? appLocalized(
                        "Automatic Dream runs at most once a day, privately on this iPhone.",
                        locale: locale
                    )
            )
            .font(.caption)
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    func reflectionMenu(for entry: Entry) -> some View {
        Menu {
            Button {
                openReflectionEditor(for: entry)
            } label: {
                Label("Edit reflection", systemImage: "pencil")
            }

            Divider()

            Button {
                regenerateReflection(for: entry, style: .concise)
            } label: {
                Label("Make shorter", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                regenerateReflection(for: entry, style: .expanded)
            } label: {
                Label("Expand", systemImage: "text.append")
            }

            Button {
                regenerateReflection(for: entry, style: .standard)
            } label: {
                Label("Reflect again", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Reflection options")
    }

    func openReflectionEditor(for entry: Entry) {
        draftHeadline = entry.reflection.headline
        draftObservations = entry.reflection.observations.map {
            ReflectionObservationDraft(text: $0)
        }
        draftTopicNames = store.topics(forEntryID: entry.id).map(\.name)
        draftTopicInput = ""
        showReflectionEditor = true
    }

    func transcriptSection(for entry: Entry) -> some View {
        let vocabularyApplication = PersonalVocabulary.apply(
            to: entry.transcript.text
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button(entry.transcript.isEmpty ? "Add" : "Edit") {
                    draftTranscript = entry.transcript.text
                    showTranscriptEditor = true
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.primaryText)
            }

            if entry.transcript.isEmpty {
                Text("Transcription unavailable. The original audio is preserved.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                if vocabularyApplication.appliedCount > 0 {
                    Button {
                        applyVocabulary(
                            vocabularyApplication,
                            to: entry
                        )
                    } label: {
                        Label(
                            "Apply personal vocabulary",
                            systemImage: "text.badge.checkmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                Text(entry.transcript.text)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(Theme.primaryText.opacity(0.92))
                    .textSelection(.enabled)
            }
        }
    }

    func contextRow(for entry: Entry) -> some View {
        Button {
            draftContext = entry.authorContext
            showContextEditor = true
        } label: {
            Group {
                if entry.authorContext.isEmpty {
                    Label("Not what you meant? Add context", systemImage: "text.badge.plus")
                } else {
                    Label("Edit your added context", systemImage: "text.badge.plus")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.tertiaryText)
        }
        .buttonStyle(.plain)
    }

    var weekNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This becomes your week.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("On Sunday, Fio reads the week back to you — what repeated, what shifted. You don't have to do anything.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button("Got it") {
                withAnimation(reduceMotion ? nil : Motion.quick) {
                    hasSeenWeekNote = true
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardStroke, lineWidth: 1))
    }

    func footerActions(for entry: Entry) -> some View {
        HStack(spacing: 18) {
            Button {
                showRecorder = true
            } label: {
                if entry.audioFileName == nil {
                    Label("Record instead", systemImage: "mic")
                } else {
                    Label("Re-record", systemImage: "mic")
                }
            }
            Text("·").foregroundStyle(Theme.tertiaryText)
            exportMenu(for: entry)
            Text("·").foregroundStyle(Theme.tertiaryText)
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
            .accessibilityIdentifier("delete-entry-button")
        }
        .font(.footnote)
        .foregroundStyle(Theme.tertiaryText)
        .buttonStyle(.plain)
    }

}
