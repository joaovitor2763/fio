import SwiftUI
import SwiftData

/// The Sunday read-back: a title, a sparkline of the week, and the week itself.
struct ReviewScreen: View {
    let review: WeeklyReview

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

/// A thin line through the week's minutes, a dot per day.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { canvas, size in
            guard values.count > 1 else { return }
            let maximum = max(values.max() ?? 1, 0.001)
            let stepX = size.width / CGFloat(values.count - 1)
            let inset: CGFloat = 6

            func point(_ index: Int) -> CGPoint {
                let normalized = values[index] / maximum
                let y = inset + (1 - CGFloat(normalized)) * (size.height - inset * 2)
                return CGPoint(x: CGFloat(index) * stepX, y: y)
            }

            var path = Path()
            path.move(to: point(0))
            for index in 1..<values.count {
                path.addLine(to: point(index))
            }
            canvas.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1)

            for index in values.indices {
                let center = point(index)
                let dot = Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
                canvas.fill(dot, with: .color(.white))
            }
        }
    }
}

/// All past read-backs, newest first.
struct ReviewListScreen: View {
    @Query(sort: \WeeklyReview.weekStart, order: .reverse) private var reviews: [WeeklyReview]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if reviews.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No reviews yet.")
                            .foregroundStyle(Theme.primaryText)
                        Text("Record on at least \(WeekComposer.minimumEntries) days and Slate reads the week back to you on Sunday.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 30)
                }

                ForEach(reviews) { review in
                    NavigationLink {
                        ReviewScreen(review: review)
                    } label: {
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
                    .buttonStyle(.plain)
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
