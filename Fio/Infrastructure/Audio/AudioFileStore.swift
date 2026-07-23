import Foundation

/// Keeps original recordings in an app-private directory. Only the generated
/// file name is persisted with an entry, never an absolute sandbox path.
enum AudioFileStore {
    private static let directoryName = "Recordings"

    static func makeRecordingURL() throws -> URL {
        let directory = try recordingsDirectory()
        return directory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("m4a")
    }

    static func url(for fileName: String) -> URL? {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              let directory = try? recordingsDirectory() else {
            return nil
        }
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func deleteFile(named fileName: String?) {
        guard let fileName, let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteFile(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func recordingsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }
}
