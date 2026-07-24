import SwiftUI
import FioKit

struct JournalMaintenanceBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Button("Try again", action: retry)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}

// MARK: - Waveform

/// Tight vertical bars mirrored around the midline, newest on the right.
struct WaveformView: View {
    let levels: [Float]
    let isLive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: 3, height: max(4, CGFloat(level) * 80))
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isLive ? 1 : 0.45)
        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: levels)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isLive)
    }
}

// MARK: - Week strip

/// Seven day cells, Monday first, dots under days that have entries.
struct WeekStrip: View {
    @Binding var selectedDay: Date
    let daysWithEntries: Set<Date>
    let calendar: JournalCalendar
    let allowedDates: ClosedRange<Date>
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(calendar.weekDays(containing: selectedDay), id: \.self) { day in
                dayCell(day)
            }
        }
        .id(calendar.weekStart(containing: selectedDay))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 44 else { return }
                    moveWeek(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.selection, trigger: selectedDay)
        .accessibilityAction(named: Text("Previous week")) {
            moveWeek(by: -1)
        }
        .accessibilityAction(named: Text("Next week")) {
            moveWeek(by: 1)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isSameDay(day, selectedDay)
        let isFuture = day > calendar.startOfDay(.now)
        let hasEntries = daysWithEntries.contains(calendar.startOfDay(day))

        return Button {
            withAnimation(reduceMotion ? Motion.quick : Motion.standard) {
                selectedDay = calendar.startOfDay(day)
            }
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.narrow).locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                Text("\(calendar.dayNumber(of: day))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isFuture ? Theme.tertiaryText : Theme.primaryText)
                Circle()
                    .fill(hasEntries ? Theme.secondaryText : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primaryText : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func moveWeek(by offset: Int) {
        guard let candidate = calendar.calendar.date(
            byAdding: .day,
            value: offset * 7,
            to: selectedDay
        ) else { return }

        let bounded = min(max(calendar.startOfDay(candidate), allowedDates.lowerBound), allowedDates.upperBound)
        guard !calendar.isSameDay(bounded, selectedDay) else { return }

        withAnimation(reduceMotion ? Motion.quick : Motion.standard) {
            selectedDay = bounded
        }
    }
}
