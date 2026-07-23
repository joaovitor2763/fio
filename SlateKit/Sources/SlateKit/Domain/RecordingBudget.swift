import Foundation

/// The soft cap on a single entry. Speaking is bounded on purpose:
/// three minutes, extendable thirty seconds at a time, never past ten.
public struct RecordingBudget: Equatable, Sendable {
    public private(set) var limit: TimeInterval

    public static let standard = RecordingBudget(limit: 180)
    public static let extensionStep: TimeInterval = 30
    public static let maximum: TimeInterval = 600
    /// When this little time remains, the "Add 30 seconds" affordance lights up.
    public static let warningWindow: TimeInterval = 45

    public init(limit: TimeInterval) {
        self.limit = min(limit, Self.maximum)
    }

    public mutating func extend() {
        limit = min(limit + Self.extensionStep, Self.maximum)
    }

    public var canExtend: Bool { limit < Self.maximum }

    public func remaining(elapsed: TimeInterval) -> TimeInterval {
        max(0, limit - elapsed)
    }

    public func isExhausted(elapsed: TimeInterval) -> Bool {
        elapsed >= limit
    }

    public func isNearlyExhausted(elapsed: TimeInterval) -> Bool {
        remaining(elapsed: elapsed) <= Self.warningWindow
    }
}
