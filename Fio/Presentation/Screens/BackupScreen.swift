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
                    .buttonStyle(.bordered)

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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
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

    @State private var recoveryPhrase = ""
    @State private var showsPhrase = false
    @State private var summary: JournalBackupSummary?
    @State private var errorMessage: String?
    @State private var showsRestoreConfirmation = false
    @State private var isRestoring = false

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

                        Group {
                            if showsPhrase {
                                TextField(
                                    "Paste the 16 words",
                                    text: $recoveryPhrase,
                                    axis: .vertical
                                )
                            } else {
                                SecureField(
                                    "Paste the 16 words",
                                    text: $recoveryPhrase
                                )
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                        )

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

                        Button(role: .destructive) {
                            showsRestoreConfirmation = true
                        } label: {
                            Text("Replace journal with this backup")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRestoring)
                    } else {
                        Button("Check backup") {
                            verifyBackup()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(recoveryPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .onChange(of: recoveryPhrase) {
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

    private func verifyBackup() {
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
