import SwiftUI
import FioKit

extension InsightsScreen {
    var identityHeader: some View {
        VStack(spacing: 2) {
            Text("Your private journal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("No account · only this iPhone")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var statisticsPanel: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    primaryMetric(
                        value: statistics.totalWords.formatted(.number.notation(.compactName)),
                        label: "Words"
                    )

                    Divider()
                        .overlay(Theme.cardStroke)

                    primaryMetric(
                        value: usageDuration(statistics.totalDuration),
                        label: "Time recorded"
                    )

                    Divider()
                        .overlay(Theme.cardStroke)

                    primaryMetric(
                        value: "\(statistics.recordingCount)",
                        label: "Fios"
                    )
                }
            } else {
                compactStatisticsRow
            }
        }
        .padding(.vertical, 14)
        .redacted(reason: store.isUsageStatisticsReady ? [] : .placeholder)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.card)
        )
    }

    var compactStatisticsRow: some View {
        HStack(spacing: 0) {
            primaryMetric(
                value: statistics.totalWords.formatted(.number.notation(.compactName)),
                label: "Words"
            )

            Divider()
                .overlay(Theme.cardStroke)

            primaryMetric(
                value: usageDuration(statistics.totalDuration),
                label: "Time recorded"
            )

            Divider()
                .overlay(Theme.cardStroke)

            primaryMetric(
                value: "\(statistics.recordingCount)",
                label: "Fios"
            )
        }
    }

    func primaryMetric(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
    }

}
