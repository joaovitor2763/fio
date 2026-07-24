import SwiftUI

struct TextEntryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store

    @State private var text = ""
    @State private var isSaving = false
    @State private var showDiscardConfirmation = false
    @FocusState private var isEditorFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Theme.background.ignoresSafeArea()

                TextEditor(text: $text)
                    .accessibilityIdentifier("text-entry-editor")
                    .focused($isEditorFocused)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(Theme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                if text.isEmpty {
                    Text("What's on your mind?")
                        .font(.body)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 21)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Write")
            .navigationBarTitleDisplayMode(.inline)
            .scrollResponsiveNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trimmedText.isEmpty {
                            dismiss()
                        } else {
                            showDiscardConfirmation = true
                        }
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveAndDismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedText.isEmpty || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(!trimmedText.isEmpty || isSaving)
        .confirmationDialog(
            "Discard this entry?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard entry", role: .destructive) {
                dismiss()
            }
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("The text you wrote has not been saved.")
        }
        .task {
            isEditorFocused = true
        }
    }

    private func saveAndDismiss() async {
        guard !trimmedText.isEmpty, !isSaving else { return }
        isSaving = true
        await store.finishRecording(
            transcriptText: trimmedText,
            duration: 0,
            audioFileName: nil
        )
        dismiss()
    }
}
