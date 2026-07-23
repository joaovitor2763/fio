import SwiftUI
import SlateKit

/// The Sunday read-back: a title, a sparkline of the week, and the week itself.
struct ReviewScreen: View {
    let review: WeekReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(review.weekStart.formatted(.dateTime.month(.wide).day()))
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 8)

                Text(review.title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                Sparkline(values: review.dailyMinutes)
                    .frame(height: 44)
                    .padding(.vertical, 6)

                Text(review.summary)
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundStyle(Theme.primaryText.opacity(0.92))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }
}

/// All past read-backs, newest first.
struct ReviewListScreen: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.reviews.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No reviews yet.")
                            .foregroundStyle(Theme.primaryText)
                        Text("Speak on three or more days and Slate reads the week back to you on Sunday.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 30)
                }

                ForEach(store.reviews) { review in
                    NavigationLink(value: Route.review(review.id)) {
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
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }
}
