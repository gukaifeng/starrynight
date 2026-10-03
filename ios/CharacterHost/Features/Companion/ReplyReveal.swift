import Foundation

/// Ephemeral presentation state only. Persisted scripts stay complete; opening
/// history, cancelling or replaying audio never hides previously delivered text.
struct ReplyReveal {
    private(set) var messageID: UUID?
    private(set) var revision = 0
    private(set) var counts: [String:Int] = [:]
    private var beats: [AIBeat] = []
    private var fractions:[String:Double]=[:]
    mutating func begin(_ id:UUID,script:AIScript) {
        guard script.beats.contains(where:{$0.parts != nil}) else {finish();return}
        messageID=id;beats=script.beats;counts=[:];fractions=[:];revision += 1
        if let first=beats.first {advance(first.beatId,fraction:0)}
    }
    mutating func advance(_ beatID:String,fraction:Double) {
        guard messageID != nil, fraction.isFinite, let beat=beats.first(where:{$0.beatId==beatID}),let parts=beat.parts else {return}
        let progress=max(fractions[beatID] ?? 0,min(1,max(0,fraction)));fractions[beatID]=progress
        let next=parts.prefix(while:{$0.at<=progress}).count
        if next>(counts[beatID] ?? 0) {counts[beatID]=next;revision += 1}
    }
    func count(_ id:UUID,beat:String)->Int? {messageID==id ? counts[beat] ?? 0 : nil}
    mutating func update(_ script:AIScript) {
        guard messageID?.uuidString.lowercased()==script.messageId.lowercased() else {return}
        beats=script.beats;revision += 1
        for beat in beats {
            if let parts=beat.parts,let fraction=fractions[beat.beatId] {
                counts[beat.beatId]=parts.prefix(while:{$0.at<=fraction}).count
            }
        }
    }
    mutating func finish() {
        guard messageID != nil else {return}
        messageID=nil;counts=[:];fractions=[:];beats=[];revision += 1
    }
}
