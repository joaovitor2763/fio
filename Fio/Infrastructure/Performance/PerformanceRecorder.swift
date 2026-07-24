import Foundation
import OSLog

/// Opt-in, local-only timing used by the reproducible simulator benchmark.
/// Release builds do not emit measurements or retain benchmark state.
@MainActor
enum PerformanceRecorder {
    private static let clock = ContinuousClock()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Fio",
        category: "Performance"
    )
    private static var launchStart: ContinuousClock.Instant?

    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["FIO_PERFORMANCE_LOG"] == "1"
#else
        false
#endif
    }

    static func beginLaunch() {
        guard isEnabled else { return }
        launchStart = clock.now
    }

    static func markFirstContentReady() {
        guard let launchStart else { return }
        emit(name: "first_content_ready", duration: launchStart.duration(to: clock.now))
        self.launchStart = nil
    }

    static func measure<T>(
        _ name: StaticString,
        operation: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else { return try await operation() }
        let start = clock.now
        defer { emit(name: "\(name)", duration: start.duration(to: clock.now)) }
        return try await operation()
    }

    static func measureSync<T>(
        _ name: StaticString,
        operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try operation() }
        let start = clock.now
        defer { emit(name: "\(name)", duration: start.duration(to: clock.now)) }
        return try operation()
    }

    private static func emit(name: String, duration: Duration) {
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        logger.notice(
            "FIO_PERF name=\(name, privacy: .public) milliseconds=\(milliseconds, format: .fixed(precision: 3), privacy: .public)"
        )
    }
}
