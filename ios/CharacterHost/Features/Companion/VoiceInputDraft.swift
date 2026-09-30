import Foundation
import Observation

/// Capture is separate from the keyboard draft. Partial ASR never mutates the
/// conversation or a user's unfinished typed message.
@MainActor @Observable final class VoiceInputDraft {
    enum Phase {case idle,holding,finishing,editing}
    var phase:Phase = .idle
    var text=""
    private(set) var wantsEdit=false
    var active:Bool {phase != .idle}
    func begin() {text="";wantsEdit=false;phase = .holding}
    func release(edit:Bool) {guard phase == .holding else {return};wantsEdit=edit;phase = .finishing}
    func accept(_ value:String) -> String? {
        guard active else {return nil}
        text=String(value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(500))
        if wantsEdit {phase = .editing;return nil}
        phase = .idle;return text.isEmpty ? nil : text
    }
    func cancel() {phase = .idle;text="";wantsEdit=false}
    func recover(_ partial:String) {
        guard active else {return}
        wantsEdit=true;text=String(partial.prefix(500));phase = .editing
    }
}
