import Foundation

struct CharacterViewPresetTests {
    @MainActor static func run() throws -> String {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("view-presets-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("journal.json")
        var checks=0
        func check(_ value:Bool,_ detail:String) throws {
            if !value {throw NSError(domain:"ViewPresets",code:1,userInfo:[NSLocalizedDescriptionKey:detail])};checks+=1
        }
        // The supported pre-feature encoding omits the optional library key.
        var old=CompanionArchive();old.characters["anime-kipfel"]=CharacterRecord(profile:.initial("anime-kipfel"))
        let encoder=JSONEncoder();let oldData=try encoder.encode(old)
        let decoded=try JSONDecoder().decode(CompanionArchive.self,from:oldData)
        try check(decoded.characters["anime-kipfel"]?.viewLibrary == nil,"Old archive missing presets must decode")
        try CompanionPersistence.write(decoded,to:url)
        let store=CompanionStore(storageURL:url,arguments:[])
        let pose=CharacterViewPose(yaw:72,pitch:-7,scale:0.88,x:0.04,y:-0.03)
        let preset=CharacterViewPreset(name:"取景 1",pose:pose)
        store.update("anime-kipfel") {$0.viewLibrary=CharacterViewLibrary(presets:[preset],selectedID:preset.id)}
        try check(store.error == nil,"Atomic save succeeds")
        try check(store.record("anime-mamehinata").viewLibrary == nil,"Other character cannot see presets")
        store.activateAccount(DemoAccount.alternateID)
        try check(store.record("anime-kipfel").viewLibrary == nil,"Other account cannot see presets")
        store.activateAccount(DemoAccount.id)
        try check(store.record("anime-kipfel").lastViewPose == pose,"Old selection is available for migration")
        store.update("anime-kipfel") {$0.viewPose=$0.lastViewPose;$0.viewLibrary=nil}
        let migrated=CompanionStore(storageURL:url,arguments:[])
        try check(migrated.record("anime-kipfel").lastViewPose==pose && migrated.record("anime-kipfel").viewLibrary==nil,"Migration retains only the last view")
        let latest=CharacterViewPose(yaw:-35,scale:0.92,x:0.01)
        migrated.update("anime-kipfel") {$0.viewPose=latest}
        let restarted=CompanionStore(storageURL:url,arguments:[])
        try check(restarted.record("anime-kipfel").lastViewPose==latest,"Latest view persists without schemes")
        restarted.update("anime-kipfel") {$0.viewPose = .original}
        let reset=CompanionStore(storageURL:url,arguments:[])
        try check(reset.record("anime-kipfel").lastViewPose == .original && reset.record("anime-kipfel").viewLibrary==nil,"Reset survives restart without old scheme resurrection")
        let damaged=CharacterViewPose(yaw:.nan,pitch:.infinity,scale:-1,x:20,y:-20).normalized
        try check(damaged.yaw.isFinite && damaged.pitch.isFinite && damaged.scale>0 && abs(damaged.x)<=0.45 && abs(damaged.y)<=0.45,"Invalid values cannot reach runtime")
        let turns=CharacterViewPose(yaw:1125,pitch:-810,scale:0.9,x:0.02).normalized
        try check(turns.yaw==45 && turns.pitch == -80,"Whole yaw turns wrap equivalently; old pitch uses the expanded safe range")
        try check(turns.matches(CharacterViewPose(yaw:1125,pitch:-80,scale:0.9,x:0.02)),"Pose comparisons understand full yaw rotations")
        try check(CharacterViewPose(pitch:720).normalized.pitch == 0 && CharacterViewPose(pitch:-180).normalized.pitch == 80,"Legacy pitch canonicalization matches Unity")
        restarted.update("anime-kipfel") {$0.viewPose=turns}
        let free=CompanionStore(storageURL:url,arguments:[])
        try check(free.record("anime-kipfel").lastViewPose==turns,"Bounded pitch survives persistence")
        let model=ModelDescriptor.all.first!
        var profile=model.collection.initialProfile()
        profile.audio=CharacterAudioPreferences(enabled:false,trackID:model.collection.defaultMusic,volume:0.4,
            masterMuted:true,speechVolume:0.6,effectsEnabled:true,effectsVolume:0.8)
        profile=model.collection.normalize(profile)
        try check(profile.audio?.volume==0 && profile.audio?.speechVolume==0 && profile.audio?.effectsVolume==nil,"Legacy global mute preserves both real channels and retires the unused effects field")
        profile.audio?.speechVolume=0.5;profile.audio?.volume=0.25
        profile=model.collection.normalize(profile)
        try check(profile.audio?.speechVolume==0.5 && profile.audio?.volume==0.25 && profile.autoSpeak,"Raising a migrated slider is never blocked by a hidden toggle")
        profile.audio=CharacterAudioPreferences(enabled:false,trackID:model.collection.defaultMusic,volume:0.4)
        profile.autoSpeak=false;profile=model.collection.normalize(profile)
        try check(profile.audio?.volume==0 && profile.audio?.speechVolume==0 && profile.audio?.effectsVolume==nil,"Legacy individual silence remains independent of retired effects")
        let known=CharacterRecord(profile:profile,messages:[CompanionMessage(role:"user",text:"以前聊过")])
        for reason:ConversationEntryReason in [.appLaunch,.characterSelection] {
            let entry=ConversationEntry(reason:reason,characterID:model.id,accountID:"guest")
            try check(ConversationGreetingPolicy.shouldGreet(known,entry:entry),"Launch and role switch greet existing relationships")
            var greeted=known;greeted.greeting=ConversationGreetingHistory(count:1,lastDate:Date(),lastText:"欢迎回来",lastEntryID:entry.id)
            try check(!ConversationGreetingPolicy.shouldGreet(greeted,entry:entry),"Duplicate renderer callbacks do not append again")
        }
        for reason:ConversationEntryReason in [.conversationReturn,.foregroundReturn] {
            try check(!ConversationGreetingPolicy.shouldGreet(known,entry:ConversationEntry(reason:reason,characterID:model.id,accountID:"guest")),"Retained tab and foreground return remain quiet")
        }
        return "PASS: \(checks) view persistence, free rotation, volume migration, scoped greeting and deduplication checks"
    }
}
