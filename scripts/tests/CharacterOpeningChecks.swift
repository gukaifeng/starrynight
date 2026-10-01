#if DEBUG && targetEnvironment(simulator)
import Foundation

@MainActor enum CharacterOpeningChecks {
    static func run() async throws -> String {
        var count=0
        func require(_ value:Bool,_ reason:String) throws {
            guard value else {throw NSError(domain:"OpeningChecks",code:1,userInfo:[NSLocalizedDescriptionKey:reason])}
            count += 1
        }
        try require(!CharacterAI.reactionPreparationEnabled && !CharacterAI.smartReplyPreparationEnabled,"Fixture must disable paid preparation")
        for model in ModelDescriptor.all {
            for index in 1...3 {
                guard let opening=CharacterOpenings.find(model.runtimeID+"-\(index)") else {
                    throw NSError(domain:"OpeningChecks",code:2,userInfo:[NSLocalizedDescriptionKey:"Missing opening for "+model.id])
                }
                let pcm=try await opening.pcm()
                try require(abs(Double(pcm.count)/48000-(opening.duration ?? 0))<0.001,"Bundled audio duration mismatch")
                try require(opening.visuals.count>=2,"Opening needs real visual cues")
            }
        }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("opening-fixture-\(UUID())")
        let store=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
        let model=ModelDescriptor.defaultCharacter,role=model.id
        let sound=CompanionSoundscape();sound.setVolume(0)
        let session=CompanionSession(store:store,model:model,soundscape:sound)
        session.setSpeechVolume(0.6)
        var visualCount=0
        session.onAIVisual={visualCount += $0.count}
        let entry=ConversationEntry(reason:.appLaunch,characterID:role,accountID:store.accountID)
        let start=Date();session.enterConversation(entry)
        try require(store.record(role).messages.count==1,"First meeting must append synchronously without network")
        try require(store.record(role).messages[0].source=="bundled-opening-v1","First meeting must be packaged")
        for _ in 0..<150 {
            if session.speech.playbackLevel>0 && visualCount>0 {break}
            try await Task.sleep(for:.milliseconds(20))
        }
        try require(session.speech.playbackLevel>0 && visualCount>=2,"Bundled speech must drive actual mixer and visual callbacks")
        let onset=Date().timeIntervalSince(start)
        session.enterConversation(entry)
        try require(store.record(role).messages.count==1,"Duplicate entry cannot draw a second opening")
        session.stop();sound.setActive(false)
        store.update(role){$0.memories=[CompanionMemory(text:"fixture memory")];$0.pendingDeletionID="pending"}
        let reset=UUID().uuidString.lowercased(),profile=store.record(role).profile
        store.update(role){$0.resetConversation(reset,version:2)}
        await CompanionPersistence.flush()
        let restored=CompanionStore(storageURL:store.url,arguments:[]).record(role)
        try require(restored.messages.isEmpty && restored.memories.isEmpty && restored.greeting==nil,"Reset must persist removal of messages, memories and introduction")
        try require(restored.profile==profile && restored.pendingDeletionID==nil && restored.conversationResetVersion==2,"Reset must retain settings and confirmed sync epoch")
        try require(ConversationGreetingPolicy.shouldIntroduce(restored),"Deleted conversation must permit a new first meeting")
        try? FileManager.default.removeItem(at:folder)
        return "PASS: \(count) bundle/audio/visual/reset checks; local playback onset \(String(format:"%.2f",onset))s; no AI calls"
    }
}
#endif
