import Foundation
import Observation

/// Observable presentation of the capture state machine. Audio level updates
/// stay in CaptureWave; these updates are only gesture and transcription events.
@MainActor @Observable final class VoiceInputDraft {
    typealias Phase=VoiceCaptureState.Phase
    private var capture=VoiceCaptureState()
    var phase:Phase {capture.phase}
    var text:String {capture.text}
    var wantsEdit:Bool {capture.wantsEdit}
    var editArmed:Bool {capture.editArmed}
    var resultReady:Bool {capture.resultReady}
    var needsReview:Bool {capture.needsReview}
    var active:Bool {capture.active}
    func begin() {capture.begin()}
    func armEdit(_ value:Bool) {
        guard capture.phase == .holding,capture.editArmed != value else {return}
        capture.armEdit(value)
    }
    func partial(_ value:String) {capture.partial(value)}
    func edit(_ value:String) {capture.edit(value)}
    @discardableResult func release(edit:Bool)->String? {capture.release(edit:edit)}
    func accept(_ value:String)->String? {capture.accept(value)}
    func cancel() {capture.cancel()}
    func recover(_ partial:String) {capture.recover(partial)}
}
