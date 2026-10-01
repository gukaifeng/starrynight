import Foundation
import CoreGraphics

/// Capture is separate from the keyboard draft. Partial ASR never mutates the
/// conversation or a user's unfinished typed message.
struct VoiceCaptureState {
    enum Phase {case idle,holding,finishing,editing}
    private(set) var phase:Phase = .idle
    private(set) var text=""
    private(set) var wantsEdit=false
    private(set) var editArmed=false
    private(set) var resultReady=false
    private(set) var needsReview=false
    private var userEdited=false
    var active:Bool {phase != .idle}
    mutating func begin() {
        text="";wantsEdit=false;editArmed=false;resultReady=false;needsReview=false;userEdited=false;phase = .holding
    }
    mutating func armEdit(_ value:Bool) {guard phase == .holding else {return};editArmed=value}
    mutating func partial(_ value:String) {
        guard active,!resultReady,!userEdited else {return};text=clean(value)
    }
    mutating func edit(_ value:String) {
        guard phase == .editing else {return};userEdited=true;text=String(value.prefix(500))
    }
    /// Finger release owns the decision. A completed ASR request is not a release.
    @discardableResult mutating func release(edit:Bool) -> String? {
        guard phase == .holding else {return nil}
        wantsEdit=edit || needsReview;editArmed=false
        if wantsEdit {phase = .editing;return nil}
        phase = .finishing
        return resultReady ? consume() : nil
    }
    mutating func accept(_ value:String) -> String? {
        guard active,!resultReady else {return nil}
        resultReady=true
        if !userEdited {text=clean(value)}
        return phase == .finishing ? consume() : nil
    }
    mutating func cancel() {phase = .idle;text="";wantsEdit=false;editArmed=false;resultReady=false;needsReview=false;userEdited=false}
    mutating func recover(_ partial:String) {
        guard active else {return}
        needsReview=true;resultReady=true
        if !userEdited,!partial.isEmpty {text=clean(partial)}
        // Keep the touch surface mounted until the finger lifts, even on an error.
        if phase != .holding {wantsEdit=true;phase = .editing}
    }
    private mutating func consume() -> String? {
        phase = .idle;return text.isEmpty ? nil : text
    }
    private func clean(_ value:String) -> String {
        String(value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(500))
    }
}

enum VoiceEditHitTarget {
    /// A small exit margin prevents highlight/haptic chatter along an edge.
    static func contains(_ point:CGPoint,frame:CGRect,armed:Bool)->Bool {
        !frame.isEmpty && frame.insetBy(dx:armed ? -16 : -4,dy:armed ? -16 : -4).contains(point)
    }
}
