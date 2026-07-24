import Foundation

func unique(_ ids: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return ids.filter { seen.insert($0).inserted }
}

func reconcilingSuggestions(in topics: [Topic]) -> [Topic] {
    let durableTopics = topics.filter { $0.status != .suggested }
    let dismissedKeys = Set(
        durableTopics
            .filter { $0.status == .dismissed }
            .map(\.normalizedName)
    )
    let acceptedByKey = durableTopics.reduce(
        into: [String: Topic]()
    ) { accepted, topic in
        guard topic.status == .accepted else { return }
        if var existing = accepted[topic.normalizedName] {
            existing.entryIDs = unique(existing.entryIDs + topic.entryIDs)
            accepted[topic.normalizedName] = existing
        } else {
            accepted[topic.normalizedName] = topic
        }
    }

    var suggestionsByKey: [String: Topic] = [:]
    var suggestionOrder: [String] = []
    for suggestion in topics where suggestion.status == .suggested {
        let key = suggestion.normalizedName
        guard !dismissedKeys.contains(key) else { continue }
        if var existing = suggestionsByKey[key] {
            existing.entryIDs = unique(existing.entryIDs + suggestion.entryIDs)
            existing.updatedAt = max(existing.updatedAt, suggestion.updatedAt)
            suggestionsByKey[key] = existing
        } else {
            var canonical = suggestion
            canonical.name = acceptedByKey[key]?.name ?? suggestion.name
            suggestionsByKey[key] = canonical
            suggestionOrder.append(key)
        }
    }

    let suggestions = suggestionOrder.compactMap { key -> Topic? in
        guard let suggestion = suggestionsByKey[key] else { return nil }
        if let accepted = acceptedByKey[key],
           Set(suggestion.entryIDs).isSubset(of: Set(accepted.entryIDs)) {
            return nil
        }
        return suggestion
    }
    return durableTopics + suggestions
}
