import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let fioBackup = UTType(
        exportedAs: "com.joaovitorsilva.fio.backup",
        conformingTo: .data
    )
}

struct FioBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fioBackup] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupScreen: View {
    @Environment(JournalStore.self) private var store

    @State private var preparedBackup: PreparedJournalBackup?
    @State private var importedFile: ImportedBackupFile?
    @State private var isChoosingBackup = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Export and import only")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Fio does not sync this backup automatically. Move the exported file yourself, then import it on the other iPhone.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 6)
            }

            Section {
                Button(action: prepareBackup) {
                    Label("Create encrypted backup", systemImage: "lock.doc")
                        .foregroundStyle(Theme.primaryText)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Includes entries, transcripts, reflections, reviews, topics, vocabulary, and preferences. Audio recordings are never included.")
            }

            Section {
                Button {
                    isChoosingBackup = true
                } label: {
                    Label("Choose backup to import", systemImage: "square.and.arrow.down")
                        .foregroundStyle(Theme.primaryText)
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Importing replaces the current journal. Because backups contain no recordings, existing audio on this iPhone will also be removed.")
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .sheet(item: $preparedBackup) { backup in
            RecoveryPhraseSheet(backup: backup) {
                statusMessage = String(localized: "Encrypted backup exported.")
            }
        }
        .sheet(item: $importedFile) { file in
            ImportBackupSheet(file: file) { summary in
                statusMessage = String(
                    localized: "Backup restored: \(summary.entryCount) entries."
                )
            }
        }
        .fileImporter(
            isPresented: $isChoosingBackup,
            allowedContentTypes: [.fioBackup]
        ) { result in
            handleImportSelection(result)
        }
        .alert(
            "Backup error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func prepareBackup() {
        do {
            preparedBackup = try store.backupService.prepareBackup()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            importedFile = ImportedBackupFile(
                name: url.lastPathComponent,
                data: try Data(contentsOf: url, options: .mappedIfSafe)
            )
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportedBackupFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

private struct BackupPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(
                isEnabled
                    ? (isDestructive ? Color.white : Theme.primaryControlForeground)
                    : Theme.tertiaryText
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isEnabled
                            ? (isDestructive ? Color.red : Theme.primaryControlBackground)
                            : Theme.card
                    )
            )
            .overlay {
                if !isEnabled {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

private struct BackupSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? Theme.primaryText : Theme.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(Theme.card)
            )
            .overlay {
                Capsule()
                    .stroke(Theme.cardStroke, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

private struct RecoveryPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss

    let backup: PreparedJournalBackup
    let onExported: () -> Void

    @State private var didSavePhrase = false
    @State private var isExporting = false
    @State private var didCopy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label {
                        Text("This phrase is generated once for this backup. Fio does not save it and cannot recover it later.")
                    } icon: {
                        Image(systemName: "key.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                    Text(backup.recoveryPhrase)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .textSelection(.enabled)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18).fill(Theme.card)
                        )
                        .accessibilityLabel("Recovery phrase")

                    Button {
                        UIPasteboard.general.string = backup.recoveryPhrase
                        didCopy = true
                    } label: {
                        Label(
                            didCopy ? "Recovery phrase copied" : "Copy recovery phrase",
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(BackupSecondaryButtonStyle())

                    Toggle(
                        "I saved the recovery phrase somewhere safe",
                        isOn: $didSavePhrase
                    )
                    .tint(Theme.primaryText)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(backup.summary.entryCount) entries")
                        Text("\(backup.summary.omittedAudioCount) audio recordings excluded")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                    Button {
                        isExporting = true
                    } label: {
                        Label("Export backup file", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BackupPrimaryButtonStyle())
                    .disabled(!didSavePhrase)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Recovery phrase")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(didSavePhrase && isExporting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: FioBackupDocument(data: backup.data),
                contentType: .fioBackup,
                defaultFilename: backup.fileName
            ) { result in
                switch result {
                case .success:
                    onExported()
                    dismiss()
                case .failure(let error):
                    let cocoaError = error as? CocoaError
                    if cocoaError?.code != .userCancelled {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert(
                "Backup error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct ImportBackupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store

    let file: ImportedBackupFile
    let onRestored: (JournalBackupSummary) -> Void

    @State private var recoveryWords = Array(
        repeating: "",
        count: RecoveryPhraseFormat.wordCount
    )
    @State private var showsPhrase = false
    @State private var summary: JournalBackupSummary?
    @State private var errorMessage: String?
    @State private var showsRestoreConfirmation = false
    @State private var isRestoring = false
    @FocusState private var focusedWord: Int?

    private let wordColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Selected file")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                        Text(file.name)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recovery phrase")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)

                        Text("Enter all 16 words in order. You can paste the whole phrase into any field.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)

                        LazyVGrid(columns: wordColumns, spacing: 10) {
                            ForEach(recoveryWords.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.tertiaryText)
                                        .frame(width: 18, alignment: .trailing)

                                    Group {
                                        if showsPhrase {
                                            TextField(
                                                "Word",
                                                text: wordBinding(at: index)
                                            )
                                        } else {
                                            SecureField(
                                                "Word",
                                                text: wordBinding(at: index)
                                            )
                                        }
                                    }
                                    .focused($focusedWord, equals: index)
                                    .submitLabel(
                                        index == RecoveryPhraseFormat.wordCount - 1
                                            ? .done
                                            : .next
                                    )
                                    .onSubmit {
                                        focusWord(after: index)
                                    }
                                    .accessibilityLabel("Recovery word \(index + 1)")
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.card)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            focusedWord == index
                                                ? Theme.accent
                                                : Theme.cardStroke,
                                            lineWidth: focusedWord == index ? 1.5 : 1
                                        )
                                }
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Toggle("Show phrase", isOn: $showsPhrase)
                            .font(.footnote)
                            .tint(Theme.primaryText)
                    }

                    if let summary {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Backup verified", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            backupSummary(summary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18).fill(Theme.card)
                        )
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Import backup")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isRestoring)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                importAction
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .onChange(of: recoveryWords) {
                summary = nil
                errorMessage = nil
            }
            .alert(
                "Replace current journal?",
                isPresented: $showsRestoreConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Replace journal", role: .destructive) {
                    restoreBackup()
                }
            } message: {
                Text("This removes every current entry, review, topic, and audio recording from this iPhone. This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private var importAction: some View {
        if summary != nil {
            Button(role: .destructive) {
                showsRestoreConfirmation = true
            } label: {
                Text("Replace journal with this backup")
            }
            .buttonStyle(BackupPrimaryButtonStyle(isDestructive: true))
            .disabled(isRestoring)
        } else {
            Button("Check backup") {
                verifyBackup()
            }
            .buttonStyle(BackupPrimaryButtonStyle())
            .disabled(!hasCompletePhrase)
        }
    }

    private var recoveryPhrase: String {
        recoveryWords.joined(separator: " ")
    }

    private var hasCompletePhrase: Bool {
        recoveryWords.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private func backupSummary(_ summary: JournalBackupSummary) -> some View {
        Text("\(summary.entryCount) entries")
        Text("\(summary.reviewCount) weekly reviews")
        Text("\(summary.topicCount) topics")
        if summary.omittedAudioCount > 0 {
            Text("\(summary.omittedAudioCount) audio recordings were not included")
        } else {
            Text("No audio recordings are included")
        }
    }

    private func wordBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { recoveryWords[index] },
            set: { updateWord(at: index, with: $0) }
        )
    }

    private func updateWord(at index: Int, with rawValue: String) {
        let lowercaseValue = rawValue.lowercased(
            with: Locale(identifier: "en_US_POSIX")
        )
        guard lowercaseValue.rangeOfCharacter(
            from: .whitespacesAndNewlines
        ) != nil else {
            recoveryWords[index] = lowercaseValue
            return
        }

        let pastedWords = lowercaseValue
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !pastedWords.isEmpty else {
            recoveryWords[index] = ""
            return
        }

        for (offset, word) in pastedWords.enumerated()
        where index + offset < RecoveryPhraseFormat.wordCount {
            recoveryWords[index + offset] = word
        }
        focusFirstEmptyWord(startingAt: index + pastedWords.count)
    }

    private func focusWord(after index: Int) {
        let nextIndex = index + 1
        focusedWord = nextIndex < RecoveryPhraseFormat.wordCount
            ? nextIndex
            : nil
    }

    private func focusFirstEmptyWord(startingAt index: Int) {
        if let emptyIndex = recoveryWords.indices.first(where: {
            $0 >= index && recoveryWords[$0].isEmpty
        }) {
            focusedWord = emptyIndex
        } else {
            focusedWord = nil
        }
    }

    private func verifyBackup() {
        focusedWord = nil
        do {
            summary = try store.backupService.summary(
                for: file.data,
                recoveryPhrase: recoveryPhrase
            )
            errorMessage = nil
        } catch {
            summary = nil
            errorMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        isRestoring = true
        Task { @MainActor in
            do {
                let restoredSummary = try await store.restoreBackup(
                    from: file.data,
                    recoveryPhrase: recoveryPhrase
                )
                onRestored(restoredSummary)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRestoring = false
            }
        }
    }
}
