#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor enum VoiceTimingChecks {
    static func run() async throws->String {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("voice-timing-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        var count=0
        func check(_ value:Bool,_ reason:String)throws {count+=1;if !value {throw NSError(domain:"VoiceTiming",code:1,userInfo:[NSLocalizedDescriptionKey:reason])}}
        try check(!CharacterAI.paidTestsEnabled,"No paid tests")
        let account="timing-regression:"+UUID().uuidString
        let store=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
        store.activateAccount(account)
        let model=ModelDescriptor.defaultCharacter
        let sound=CompanionSoundscape();sound.setVolume(0)
        let session=CompanionSession(store:store,model:model,soundscape:sound)
        session.setSpeechVolume(0)
        var visualCount=0;session.onAIVisual={visualCount += $0.count}
        session.enterConversation(ConversationEntry(reason:.appLaunch,characterID:model.id,accountID:account))
        for _ in 0..<100 {if visualCount>0 {break};try await Task.sleep(for:.milliseconds(20))}
        guard let opening=VoiceTimeline.shared.records.last(where:{$0.account==account}) else {throw NSError(domain:"VoiceTiming",code:2)}
        try check(opening.kind=="bundled_opening" && opening.status=="completed","Muted opening trace completed")
        try check(opening.outputSuppressed && opening.processingMs != nil,"Muted preparation timing exists")
        try check(opening.marks["text_received"] != nil && opening.marks["visuals_dispatched"] != nil && visualCount>0,"Muted opening still dispatches real authored visuals")
        try check(opening.marks["first_output"]==nil && opening.server==nil,"No fictitious audio or server timing")
        try check(opening.spans.contains {$0.name=="conversation.visual_dispatch"},"Visual dispatch is timed")
        session.stop();sound.setActive(false)
        let timeline=VoiceTimeline(directory:folder.appendingPathComponent("traces"))
        let id=timeline.begin(account:account,character:model.id,kind:"muted_reply")
        timeline.flag(id,"playback","静音");timeline.flag(id,"audio_requested","否")
        let server=VoiceServerTrace(schemaVersion:1,traceId:id,kind:"reply",requestId:"request",character:model.id,created:0,status:"completed",totalMs:145,
            gateway:[:],marks:["core_generation_completed":90,"visuals_complete":140],flags:["wants_audio":.boolean(false)],
            spans:[VoiceSpan(name:"model.plan.stream",startMs:0,durationMs:90),VoiceSpan(name:"model.performance.http",startMs:2,durationMs:138)],droppedSpans:0)
        timeline.receive(id,event:AIEvent(type:"reply.narration.ready"))
        timeline.receive(id,event:AIEvent(type:"reply.visuals.updated"))
        timeline.receive(id,event:AIEvent(type:"reply.completed"))
        timeline.receive(id,event:AIEvent(type:"voice.trace",trace:server))
        timeline.mark(id,"processing_complete");timeline.finish(id)
        guard let record=timeline.records.last else {throw NSError(domain:"VoiceTiming",code:3)}
        try check(record.processingMs != nil && record.outputSuppressed && record.marks["first_output"]==nil,"Muted stream has non-playback duration")
        try check(record.server?.spans.count==2 && record.marks["visuals_received"] != nil,"Server generation/performance survives without audio events")
        for _ in 0..<100 {if FileManager.default.fileExists(atPath:folder.appendingPathComponent("traces/traces.json").path) {break};try await Task.sleep(for:.milliseconds(20))}
        let restored=VoiceTimeline(directory:folder.appendingPathComponent("traces"))
        for _ in 0..<100 {if !restored.records.isEmpty {break};try await Task.sleep(for:.milliseconds(20))}
        try check(restored.records.first?.server?.traceId==id && restored.records.first?.outputSuppressed==true,"Muted timing survives restart")
        return "PASS: \(count) muted opening, generation, visual dispatch and persistent timing checks"
    }
}
#endif
