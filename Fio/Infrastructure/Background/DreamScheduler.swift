import BackgroundTasks
import Foundation

/// Requests an opportunistic, charger-friendly window for local topic
/// consolidation. iOS chooses the actual time; no network is ever required.
enum DreamScheduler {
    static let identifier = "com.joaovitorsilva.fio.dream"

    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date().addingTimeInterval(2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
