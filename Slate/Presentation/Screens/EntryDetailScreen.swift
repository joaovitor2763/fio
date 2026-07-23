import SwiftUI
import SlateKit

/// One entry: the observer's notes, the tags, and the full transcript.
struct EntryDetailScreen: View {
    let entryID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    @AppStorage("hasSeenWeekNote") private var hasSeenWeekNote = false

    @State private var showContextEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showRecorder = false
    @State private var draftContext = ""

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
        .toolbarBackground(Theme.background, for: .navigationBar)
    }

    private func content(for entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !entry.displayObservations.isEmpty {
                    observationList(entry.displayObservations)
                } else if store.annotatingEntryIDs.contains(entry.id) {
                    HStack(spacing: 8) {
                        ReadingDot()
                        Text("Slate is reading this entry.")
                            .font(.footnote)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }

                if !entry.reflection.tags.isEmpty {
                    WrapLayout(spacing: 6) {
                        ForEach(entry.reflection.tags, id: \.self) { tag in
                            TagCapsule(text: tag)
                        }
                    }
                }

                if !entry.displayObservations.isEmpty {
                    contextRow(for: entry)
                }

                if !hasSeenWeekNote {
                    weekNoteCard
                }

                Text(entry.transcript.text)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(Theme.primaryText.opacity(0.92))
                    .textSelection(.enabled)

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

                footerActions
                    .padding(.top, 12)
            }
            .padding(20)
        }
        .sheet(isPresented: $showContextEditor) { contextEditor(for: entry) }
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
        } message: {
            Text("It is only stored on this phone, so this removes it everywhere it exists.")
        }
    }

    private func observationList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text("•").foregroundStyle(Theme.secondaryText)
                    Text(line)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
    }

    private func contextRow(for entry: Entry) -> some View {
        Button {
            draftContext = entry.authorContext
            showContextEditor = true
        } label: {
            Label(
                entry.authorContext.isEmpty ? "Not what you meant? Add context" : "Edit your added context",
                systemImage: "text.badge.plus"
            )
            .font(.footnote)
            .foregroundStyle(Theme.tertiaryText)
        }
        .buttonStyle(.plain)
    }

    private var weekNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This becomes your week.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("On Sunday, Slate reads the week back to you — what repeated, what shifted. You don't have to do anything.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button("Got it") {
                withAnimation { hasSeenWeekNote = true }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private var footerActions: some View {
        HStack(spacing: 18) {
            Button {
                showRecorder = true
            } label: {
                Label("Re-record", systemImage: "mic")
            }
            Text("·").foregroundStyle(Theme.tertiaryText)
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.tertiaryText)
        .buttonStyle(.plain)
    }

    private func contextEditor(for entry: Entry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Say what you actually meant. The observer reads this too.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                TextEditor(text: $draftContext)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Add context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showContextEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.saveContext(draftContext, forEntryID: entry.id)
                            showContextEditor = false
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
