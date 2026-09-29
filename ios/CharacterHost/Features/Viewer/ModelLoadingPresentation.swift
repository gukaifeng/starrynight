import Foundation

/// New character presentations get one readable breath even when cached. The
/// retained conversation path bypasses this entirely. Use a monotonic clock.
struct ModelLoadingPresentation: Equatable {
    static let minimumVisible: TimeInterval = 0.65
    private(set) var shownAt: TimeInterval?
    var isVisible: Bool { shownAt != nil }
    mutating func begin(now: TimeInterval) { shownAt = now }
    func remainingDisplayTime(now: TimeInterval) -> TimeInterval {
        guard let shownAt else { return 0 }
        return max(0,Self.minimumVisible - (now - shownAt))
    }
}
