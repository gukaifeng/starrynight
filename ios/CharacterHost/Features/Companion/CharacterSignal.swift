import Foundation

// The host knows semantic events, never bone paths, morph indices or clip asset names.
// A presentation creates a fresh sequence; a generation owns a separate cancellable turn.
struct CharacterIntent {
    var eventName: String
    var turnId = ""
    var emotion = ""
    var target = ""
    var intensity = 1.0
    var audioTime = 0.0
    var level = 0.0
    var posture: [String:Any]? = nil
    var selections: [String]? = nil
}
@MainActor final class CharacterSignalPort {
    private var sequence = 0
    func reset() { sequence = 0 }
    func payload(_ intent: CharacterIntent, actorId: String, eventId: String = UUID().uuidString) -> [String:Any] {
        sequence += 1
        var result: [String:Any] = ["apiMajor":1,"apiMinor":1,"actorId":actorId,"sequence":sequence,"eventId":eventId,
                "turnId":intent.turnId,"eventName":intent.eventName,"emotion":intent.emotion,"target":intent.target,
                "intensity":min(1,max(0,intent.intensity)),"audioTime":intent.audioTime,"level":min(1,max(0,intent.level)),"visemes":[]]
        if let posture = intent.posture { result["posture"] = posture }
        if let selections = intent.selections { result["selections"] = selections }
        return result
    }
}
