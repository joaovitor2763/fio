import Foundation

/// A durable thread that connects journal entries. Topics belong to the
/// author; the observer may suggest them, but reflections never own them.
public struct Topic: Identifiable, Equatable, Hashable, Sendable, Codable {
    public enum Status: String, Equatable, Hashable, Sendable, Codable {
        case suggested
        case accepted
        case dismissed
    }

    public let id: UUID
    public var name: String
    public var status: Status
    public var entryIDs: [UUID]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        status: Status = .accepted,
        entryIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.entryIDs = Self.unique(entryIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var normalizedName: String {
        Self.normalizedName(name)
    }

    public func contains(entryID: UUID) -> Bool {
        entryIDs.contains(entryID)
    }

    public func replacingEntryReference(
        from oldID: UUID,
        to newID: UUID,
        updatedAt: Date = .now
    ) -> Topic {
        guard entryIDs.contains(oldID) else { return self }
        var updated = self
        updated.entryIDs = Self.unique(
            entryIDs.map { $0 == oldID ? newID : $0 }
        )
        updated.updatedAt = updatedAt
        return updated
    }

    /// Keeps topic names compact without imposing an English-only title case.
    public static func sanitizedName(_ raw: String) -> String? {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 48 else { return nil }
        guard collapsed.split(separator: " ").count <= 6 else { return nil }
        guard !normalizedName(collapsed).isEmpty else { return nil }
        return collapsed
    }

    /// A comparison key only. The original spelling remains the display name.
    public static func normalizedName(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

/// Raw output from the local Dream observer. The application layer validates
/// recurrence and persistence before it becomes a visible suggestion.
public struct TopicCandidate: Equatable, Hashable, Sendable {
    public var name: String
    public var entryIDs: [UUID]

    public init(name: String, entryIDs: [UUID]) {
        self.name = name
        self.entryIDs = entryIDs
    }
}
