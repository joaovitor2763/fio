import BackgroundTasks
import Foundation

/// Requests an opportunistic, charger-friendly window for local topic
/// consolidation. iOS chooses the actual time; no network is ever required.
enum DreamScheduler {
    static let identifier = "com.joaovitorsilva.fio.dream"

    static func schedule(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 2),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? now.addingTimeInterval(24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
