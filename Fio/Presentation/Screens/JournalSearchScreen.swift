import SwiftUI
import FioKit

struct JournalSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(JournalStore.self) private var store
    @Namespace private var navigationNamespace
    @State private var query = ""

    private var results: [Entry] {
        store.searchEntries(matching: query)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHint
                } else if results.isEmpty {
                    noResults
                } else {
                    ForEach(results) { entry in
                        let route = Route.entry(entry.id)
                        NavigationLink(value: route) {
                            searchResult(entry)
                                .matchedTransitionSource(
                                    id: route,
                                    in: navigationNamespace
                                ) { source in
                                    source
                                        .background(Theme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search transcript, reflection, and context"
        )
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .entry(let id):
                EntryDetailScreen(entryID: id)
                    .contextualNavigationTransition(
                        sourceID: route,
                        in: navigationNamespace,
                        reduceMotion: reduceMotion
                    )
            case .review:
                EmptyView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var searchHint: some View {
        Label(
            "Search every transcript, reflection, and note stored on this iPhone.",
            systemImage: "magnifyingglass"
        )
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryText)
        .padding(.top, 28)
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No results")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Try a different word or phrase.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 28)
    }

    private func searchResult(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                entry.createdAt.formatted(
                    .dateTime
                        .month(.abbreviated)
                        .day()
                        .year()
                        .hour()
                        .minute()
                        .locale(locale)
                )
            )
            .font(.caption)
            .foregroundStyle(Theme.tertiaryText)

            Text(entry.timelineLine)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)

            if !entry.transcript.isEmpty {
                Text(entry.transcript.excerpt(maxCharacters: 180))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }
}
