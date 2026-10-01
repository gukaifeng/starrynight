#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Explicit simulator-only inputs. No microphone, provider or user journal is
/// involved. The callback, editor, send and persistence paths are production code.
struct VoiceAtmosphereFixture:View {
    @State private var session:CompanionSession
    @State private var result=""
    init() {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("voice-fixture-\(UUID())/journal.json")
        let store=CompanionStore(storageURL:url,arguments:[])
        _session=State(initialValue:CompanionSession(store:store,model:.defaultCharacter,soundscape:CompanionSoundscape()))
    }
    var body:some View {
        VStack {
            Text(result).font(.system(size:9)).lineLimit(2).accessibilityIdentifier("voiceCoreResult")
            HStack {
                Button("识别后编辑") {
                    session.voiceInput.begin();session.voiceInput.release(edit:true)
                    session.speech.onTranscript?("今天窗外下雨了")
                }.accessibilityIdentifier("fixtureVoiceEdit")
                Button("松开发送") {
                    session.voiceInput.begin();session.voiceInput.release(edit:false)
                    session.speech.onTranscript?("一起听听雨声吧")
                }.accessibilityIdentifier("fixtureVoiceSend")
                Button("取消") {session.cancelVoiceInput()}.accessibilityIdentifier("fixtureVoiceCancel")
            }.font(.caption)
            Spacer(minLength:0)
            CompanionChatView(session:session).frame(maxWidth:600,maxHeight:360)
        }.padding(.top,20).padding(.bottom,12).background(Theme.background).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
            .task {result=await VoiceAtmosphereChecks.run()}
    }
}

enum VoiceAtmosphereChecks {
    @MainActor static func run() async -> String {
        var checks=0
        func check(_ value:Bool,_ reason:String) {precondition(value,reason);checks += 1}
        let voice=VoiceInputDraft()
        check(voice.accept("迟到结果")==nil,"A cancelled capture cannot send a late transcript")
        voice.begin();voice.release(edit:true)
        check(voice.accept("  修改这句话  ")==nil && voice.phase == .editing && voice.text=="修改这句话","Edit mode must not send before confirmation")
        voice.cancel();voice.begin();voice.release(edit:false)
        check(voice.accept("普通发送")=="普通发送" && !voice.active,"Ordinary release sends once")
        check(voice.accept("重复回包")==nil,"Duplicate ASR completion must not send twice")
        voice.begin();voice.recover("网络中断时的文字")
        check(voice.phase == .holding && voice.text=="网络中断时的文字","Timeout cannot remove the held touch surface")
        voice.release(edit:false)
        check(voice.phase == .editing,"A failed capture requires review after release")
        voice.cancel();voice.begin();voice.partial("今天")
        voice.armEdit(true)
        check(voice.phase == .holding && voice.editArmed,"Entering the target highlights it without opening the editor")
        voice.armEdit(false)
        check(voice.accept("今天窗外下雨了")==nil && voice.phase == .holding,"An early final must wait for the finger")
        check(voice.release(edit:false)=="今天窗外下雨了","An early result sends exactly on release")
        voice.begin();voice.partial("今天");voice.release(edit:true);voice.edit("今天不下雨")
        check(voice.accept("今天下雨")==nil && voice.text=="今天不下雨","Late ASR cannot overwrite a manual correction")
        voice.cancel();voice.begin();voice.release(edit:false)
        check(voice.accept(" \n")==nil && !voice.active,"Silence cannot create an empty message")
        var motion=DeviceShakeDetector()
        for index in 0..<80 {check(motion.sample(time:Double(index)/40,x:0.2,y:0.12,z:0.08,rotation:0.5)==nil,"Walking noise must not trigger")}
        check(motion.sample(time:2,x:1.2,y:0,z:0,rotation:2)==nil,"One impulse cannot trigger")
        _=motion.sample(time:2.1,x:0,y:0,z:0,rotation:0)
        check(motion.sample(time:2.25,x:-1.2,y:0,z:0,rotation:2) != nil,"Two opposing impulses should trigger")
        _=motion.sample(time:2.4,x:0,y:0,z:0,rotation:0)
        check(motion.sample(time:2.55,x:1.3,y:0,z:0,rotation:2)==nil,"Cooldown prevents repeated interruptions")
        check(motion.sample(time:Double.nan,x:4,y:0,z:0,rotation:3)==nil,"Invalid hardware values are rejected")
        _=motion.sample(time:15,x:1.3,y:0,z:0,rotation:2)
        _=motion.sample(time:15.1,x:0,y:0,z:0,rotation:0)
        check(motion.sample(time:15.3,x:-1.3,y:0,z:0,rotation:2) != nil,"A later deliberate shake re-arms")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("journal-worker-\(UUID())")
        defer {try? FileManager.default.removeItem(at:folder)}
        let store=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
        for index in 0..<60 {store.update("role") {$0.messages.append(CompanionMessage(role:"user",text:"\(index)",source:"cloud-v1"))}}
        check(store.record("role").messages.count==60,"UI observes writes immediately")
        await CompanionPersistence.flush()
        let restored=CompanionStore(storageURL:store.url,arguments:[])
        check(restored.record("role").messages.map(\.text)==(0..<60).map(String.init),"Serial snapshots retain every message in order")
        // An invalid parent path exercises a genuine disk error; the in-memory
        // message stays available and a later successful write repairs persistence.
        let blocked=folder.appendingPathComponent("blocked")
        try! Data([1]).write(to:blocked)
        let failed=CompanionStore(storageURL:blocked.appendingPathComponent("journal.json"),arguments:[])
        failed.update("role") {$0.messages.append(CompanionMessage(role:"user",text:"不能丢失",source:"cloud-v1"))}
        await CompanionPersistence.flush();await Task.yield()
        check(failed.record("role").messages.count==1,"Disk errors retain the current conversation")
        try! FileManager.default.removeItem(at:blocked)
        failed.update("role") {$0.profile.atmosphereEnabled=false}
        await CompanionPersistence.flush()
        let recovered=CompanionStore(storageURL:failed.url,arguments:[])
        check(recovered.record("role").messages.count==1 && recovered.record("role").profile.atmosphereEnabled==false,"Retry saves the pending message and per-role atmosphere choice")
        check(ModelDescriptor.defaultCharacter.conversationProfile(preserving:recovered.record("role").profile).atmosphereEnabled==false,"Opening a character preserves the effects preference")
        check(recovered.record("role").profile.resolvedAtmosphereLevel==0,"Legacy disabled atmosphere migrates to zero")
        check(CharacterProfile(name:"默认").resolvedAtmosphereLevel==2,"New profiles default to medium")
        failed.update("role") {$0.profile.atmosphereLevel=4}
        await CompanionPersistence.flush()
        let levelRestored=CompanionStore(storageURL:failed.url,arguments:[]).record("role").profile
        check(levelRestored.resolvedAtmosphereLevel==4,"Explicit level overrides legacy disabled state and persists")
        check(ModelDescriptor.defaultCharacter.conversationProfile(preserving:levelRestored).resolvedAtmosphereLevel==4,"Reopening retains character-specific atmosphere level")
        check(failed.record("another-role").profile.resolvedAtmosphereLevel==2,"One character cannot change another's atmosphere")
        check(recovered.record("role").profile.resolvedAtmosphereIntensity==0,"Legacy off remains fully off")
        check(levelRestored.resolvedAtmosphereIntensity==1,"Legacy highest maps to the continuous maximum")
        check(CharacterProfile(name:"默认").resolvedAtmosphereIntensity==0.5,"New profiles retain their previous middle density")
        failed.update("role") {$0.profile.atmosphereIntensity=0.373}
        await CompanionPersistence.flush()
        let continuousRestored=CompanionStore(storageURL:failed.url,arguments:[]).record("role").profile
        check(continuousRestored.resolvedAtmosphereIntensity==0.373,"Fractional intensity survives disk roundtrip without snapping")
        check(ModelDescriptor.defaultCharacter.conversationProfile(preserving:continuousRestored).resolvedAtmosphereIntensity==0.373,"Reopening retains the exact per-character intensity")
        check(failed.record("another-role").profile.resolvedAtmosphereIntensity==0.5,"Continuous intensity remains isolated per character")
        do {
            let library=try CharacterLibraryTests.run()
            return "PASS: \(checks) voice lifecycle, motion gating and asynchronous journal checks; "+library
        } catch {return "FAIL: \(error)"}
    }
}
#endif
