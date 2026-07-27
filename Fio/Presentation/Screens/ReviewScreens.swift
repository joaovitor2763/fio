import SwiftUI
import FioKit

/// The Sunday read-back: an editorial summary of the week and its speaking rhythm.
struct ReviewScreen: View {
    let review: WeekReview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                reviewHeader

                WeeklyActivityChart(
                    weekStart: review.weekStart,
                    values: review.dailyMinutes
                )

                summarySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text(weekRange.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.secondaryText)
            }

            Text(review.title)
                .font(
                    dynamicTypeSize.isAccessibilitySize
                        ? .largeTitle.weight(.semibold)
                        : .system(size: 34, weight: .semibold, design: .serif)
                )
                .tracking(-0.4)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Your week, in words")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)

                Rectangle()
                    .fill(Theme.cardStroke)
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(summaryParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(7)
                        .foregroundStyle(Theme.primaryText.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
        }
    }

    private var weekRange: String {
        let calendar = Calendar.autoupdatingCurrent
        guard let weekEnd = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: 6,
            to: review.weekStart
        ) else {
            return review.weekStart.formatted(.dateTime.month(.abbreviated).day())
        }

        let start = review.weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = weekEnd.formatted(.dateTime.month(.abbreviated).day())
        if calendar.component(.month, from: review.weekStart)
            == calendar.component(.month, from: weekEnd),
           calendar.component(.year, from: review.weekStart)
            == calendar.component(.year, from: weekEnd) {
            let month = review.weekStart.formatted(.dateTime.month(.abbreviated))
            let startDay = review.weekStart.formatted(.dateTime.day())
            let endDay = weekEnd.formatted(.dateTime.day())
            return "\(month) \(startDay) – \(endDay)"
        }

        return "\(start) – \(end)"
    }

    /// Generated summaries often arrive as one long paragraph. Grouping complete
    /// sentences improves scanning without changing any of the review's wording.
    private var summaryParagraphs: [String] {
        let rawParagraphs = review.summary
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard rawParagraphs.count <= 1, let summary = rawParagraphs.first else {
            return rawParagraphs
        }

        var sentences: [String] = []
        summary.enumerateSubstrings(
            in: summary.startIndex..<summary.endIndex,
            options: .bySentences
        ) { sentence, _, _, _ in
            if let sentence {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        guard sentences.count > 3 else { return [summary] }

        return stride(from: 0, to: sentences.count, by: 3).map { start in
            sentences[start..<min(start + 3, sentences.count)].joined(separator: " ")
        }
    }
}

/// All past read-backs, newest first.
struct ReviewListScreen: View {
    @Environment(JournalStore.self) private var store
    let navigationNamespace: Namespace.ID

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.reviews.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No reviews yet.")
                            .foregroundStyle(Theme.primaryText)
                        Text("Speak on three or more days and Fio reads the week back to you on Sunday.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 30)
                }

                ForEach(store.reviews) { review in
                    let route = Route.review(review.id, source: .list)
                    NavigationLink(value: route) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(review.weekStart.formatted(.dateTime.month(.wide).day().year()))
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                            Text(review.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
                        .matchedTransitionSource(id: route, in: navigationNamespace) { source in
                            source
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                        }
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .scrollResponsiveNavigationBar()
    }
}
