import Foundation

/// Keep automatic following separate from the physical scroll position: new
/// streaming text can move the bottom before ScrollViewReader catches up.
struct ConversationScrollState: Equatable {
    private(set) var followingLatest = true
    private(set) var isAtLatest = true
    var showsReturnButton: Bool { !followingLatest && !isAtLatest }

    mutating func update(bottomDistance: Double, resumeFollowing: Bool = true) {
        guard bottomDistance.isFinite else { return }
        isAtLatest = bottomDistance <= 24
        if isAtLatest && resumeFollowing { followingLatest = true }
    }
    mutating func scrollTowardHistory() {
        followingLatest = false
    }
    mutating func returnToLatest() { followingLatest = true }
}
