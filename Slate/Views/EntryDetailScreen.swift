import SwiftUI
import SwiftData

/// One entry: the observer's notes, the tags, and the full transcript.
struct EntryDetailScreen: View {
    @Bindable var entry: JournalEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("hasSeenWeekNote") private var hasSeenWeekNote = false

    @State private var showContextEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showRecorder = false
    @State private var draftContext = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !entry.allObservations.isEmpty {
                    observationList
                }

                if !entry.tags.isEmpty {
                    WrapLayout(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            TagCapsule(text: tag)
                        }
                    }
                }

                if !entry.allObservations.isEmpty {
                    contextRow
                }

                if !hasSeenWeekNote {
                    weekNoteCard
                }

                Text(entry.transcript)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(Theme.primaryText.opacity(0.92))

                if !entry.userContext.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Added later")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                        Text(entry.userContext)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                footerActions
                    .padding(.top, 12)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(entry.createdAt.entryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .sheet(isPresented: $showContextEditor) { contextEditor }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordScreen(replacing: entry)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                context.delete(entry)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("It is only stored on this phone, so this removes it everywhere it exists.")
        }
    }

    private var observationList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entry.allObservations, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text("•")
                        .foregroundStyle(Theme.secondaryText)
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

    private var contextRow: some View {
        Button {
            draftContext = entry.userContext
            showContextEditor = true
        } label: {
            Label(
                entry.userContext.isEmpty ? "Not what you meant? Add context" : "Edit your added context",
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
            Button("Got it") { hasSeenWeekNote = true }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
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

    private var contextEditor: some View {
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
                        entry.userContext = draftContext.trimmingCharacters(in: .whitespacesAndNewlines)
                        try? context.save()
                        showContextEditor = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
