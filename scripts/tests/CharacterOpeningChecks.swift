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
            if model.isPreviewOnly {
                try require(CharacterOpenings.random(for:model.id)==nil,"Preview role must not bundle paid opening media")
                let previewStore=CompanionStore(storageURL:FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID()).json"),arguments:[])
                let preview=CompanionSession(store:previewStore,model:model,soundscape:CompanionSoundscape())
                preview.enterConversation(ConversationEntry(reason:.appLaunch,characterID:model.id,accountID:previewStore.accountID))
                try require(previewStore.record(model.id).messages.isEmpty && preview.soundscape.volume==0,
                            "Preview must stay local and silent")
                continue
            }
            for index in 1...3 {
                guard let opening=CharacterOpenings.find(model.runtimeID+"-v2-\(index)") else {
                    throw NSError(domain:"OpeningChecks",code:2,userInfo:[NSLocalizedDescriptionKey:"Missing opening for "+model.id])
                }
                let pcm=try await opening.pcm()
                try require(abs(Double(pcm.count)/48000-(opening.duration ?? 0))<0.001,"Bundled audio duration mismatch")
                try require(opening.visuals.count>=2,"Opening needs real visual cues")
                let parts=opening.script(characterID:model.id).beats[0].parts ?? []
                try require(parts.filter {$0.kind == "thought" && $0.isVisible}.count==2,"Every introduction needs two visible inner asides")
                try require(parts.filter {$0.kind == "dialogue"}.map(\.text).joined()==opening.text,"Aside composition must preserve every spoken character")
                try require(CharacterOpenings.find(model.runtimeID+"-\(index)")?.audioReady == true,"Old first-meeting audio must remain replayable")
                let suggestions=CharacterOpenings.initialReplies(for:model.runtimeID,messageID:"test-message")
                try require(suggestions.count==3 && Set(suggestions.map(\.text)).count==3,
                            "Every bundled introduction needs three immediately visible replies")
            }
        }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("opening-fixture-\(UUID())")
        let store=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
        let model=ModelDescriptor.defaultCharacter,role=model.id
        let sound=CompanionSoundscape();sound.setVolume(0)
        let session=CompanionSession(store:store,model:model,soundscape:sound)
        session.setSpeechVolume(0.6);sound.setVolume(0);sound.setActive(true)
        var visualCount=0
        session.onAIVisual={visualCount += $0.count}
        let entry=ConversationEntry(reason:.appLaunch,characterID:role,accountID:store.accountID)
        let start=Date();session.enterConversation(entry)
        try require(store.record(role).messages.count==1,"First meeting must append synchronously without network")
        try require(store.record(role).messages[0].source=="bundled-opening-v2","First meeting must use the revised package")
        let first=store.record(role).messages[0]
        try require(session.quickReplies.count==3 && session.quickReplySource==first.aiScript?.messageId.lowercased(),
                    "First-meeting suggestions must appear before speech completes")
        let opening=CharacterOpenings.find(first.aiScript!.openingID!)!
        try require(first.speechDuration==opening.duration && first.speechSpeed==1,"Measured opening length must exist before audio starts")
        for _ in 0..<150 {
            if session.speech.playbackLevel>0 && visualCount>0 {break}
            try await Task.sleep(for:.milliseconds(20))
        }
        try require(session.speech.playbackLevel>0 && visualCount>=2,"Bundled speech must drive actual mixer and visual callbacks")
        try require(session.speech.durations[first.id]==opening.duration,"Playback exposes the exact packaged duration immediately")
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
