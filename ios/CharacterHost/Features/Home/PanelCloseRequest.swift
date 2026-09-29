import Foundation

/// Every exit path shares validation and persistence before starting dismissal.
@MainActor final class SoftPanelCloseRequest {
    var beforeClose: (() -> Bool)?
    var onClose: (() -> Void)?
    private var closing = false
    func begin(_ action: @escaping () -> Void) {
        closing = false; beforeClose = nil; onClose = action
    }
    func request() {
        guard !closing, beforeClose?() != false else { return }
        closing = true
        onClose?()
    }
}

