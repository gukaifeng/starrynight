import Foundation
#if !os(iOS)
@main
#endif
struct CompanionExperienceTests {
    @MainActor static func main() throws { print(try run()) }
    @MainActor static func run() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-migration-\(UUID())/journal.json")
        defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        var old = CompanionArchive(); old.schemaVersion = 1
        var role = CharacterRecord(profile:CharacterProfile(name:"琪宝"))
        role.messages = [CompanionMessage(role:"user",text:"过去的测试"),CompanionMessage(role:"assistant",text:"过去的模拟回复")]
        role.memories = [CompanionMemory(text:"我喜欢下雨")]
        var experience = CompanionExperiences(); experience.preferences.nickname = "小北"; role.experiences = experience
        old.characters["anime-kipfel"] = role
        try CompanionPersistence.write(old,to:url)
        let store = CompanionStore(storageURL:url)
        precondition(store.archive.schemaVersion == 2)
        precondition(store.record("anime-kipfel").messages.isEmpty)
        precondition(store.record("anime-kipfel").memories.first?.text == "我喜欢下雨")
        precondition(store.record("anime-kipfel").together.preferences.nickname == "小北")
        precondition(FileManager.default.fileExists(atPath:url.appendingPathExtension("before-real-ai").path))
        store.update("anime-kipfel") { $0.messages.append(CompanionMessage(role:"assistant",text:"真实回复",source:"cloud-v1")) }
        let reopened = CompanionStore(storageURL:url)
        precondition(reopened.record("anime-kipfel").messages.count == 1)
        reopened.activateAccount("someone-else")
        precondition(reopened.record("anime-kipfel").messages.isEmpty)
        precondition(store.record("anime-mamehinata").memories.isEmpty)
        precondition(CompanionStory.all.count == 3)
        let lime=CharacterPublicProfile.find("anime-lime")
        precondition(lime?.englishOnly == true && lime?.scenarios?.count == 3)
        precondition(lime?.scenarios?.allSatisfy {$0.id.hasPrefix("lime-")} == true)
        var oldLime=lime!;oldLime.profileRevision=nil
        precondition(!oldLime.supersedes(lime) && lime!.supersedes(oldLime))
        precondition(CharacterPublicProfile.find("anime-mafuyu")?.scenarios?.count == 3)
        precondition(CharacterPublicProfile.find("anime-kipfel")?.scenarios?.isEmpty == true)
        precondition(AIBeat.visibleThought("I feel a little more confident now.") != nil)
        precondition(AIBeat.visibleThought("I should respond to the user warmly.") == nil)
        precondition(store.defaultNickname.isEmpty && store.effectiveNickname(for:"anime-kipfel") == "小北")
        store.saveDefaultNickname("  小星\n 同学  ")
        precondition(store.defaultNickname == "小星 同学")
        precondition(store.effectiveNickname(for:"anime-kipfel") == "小北")
        precondition(store.effectiveNickname(for:"anime-lime") == "小星 同学")
#if os(iOS)
        let model = ModelDescriptor.defaultCharacter
        for trigger in ["user_message","idle","appLaunch","model_shaken","model_pinched","story"] {
            let body = CompanionSession.requestBody(store:store,model:model,text:"",trigger:trigger)
            let preferences = body["preferences"] as! [String:String]
            precondition(preferences["nickname"] == "小北" && preferences["nicknameSource"] == "character")
        }
#endif
        var specific = store.record("anime-kipfel").together.preferences; specific.nickname = "  "
        store.saveTogether(specific,id:"anime-kipfel")
        precondition(store.effectiveNickname(for:"anime-kipfel") == "小星 同学")
#if os(iOS)
        let inherited = CompanionSession.requestBody(store:store,model:model,text:"",trigger:"idle")["preferences"] as! [String:String]
        precondition(inherited["nickname"] == "小星 同学" && inherited["nicknameSource"] == "account")
#endif
        store.activateAccount("account-B")
        precondition(store.defaultNickname.isEmpty && store.effectiveNickname(for:"anime-kipfel").isEmpty)
        store.saveDefaultNickname("River")
        let reload = CompanionStore(storageURL:url)
        precondition(reload.defaultNickname == "小星 同学")
        reload.activateAccount("account-B"); precondition(reload.defaultNickname == "River")
        enum SimulatedFailure:Error { case write }
        do { try reload.applyCloudBatch { reload.saveDefaultNickname("Changed"); throw SimulatedFailure.write } }
        catch SimulatedFailure.write {}
        precondition(reload.defaultNickname == "River")
        try reload.applyCloudBatch { reload.saveDefaultNickname("") }
        precondition(CompanionStore(storageURL:url).archive.defaultNicknames?["account-B"] == "")
        reload.activateAccount("guest"); reload.saveDefaultNickname("游客小星")
        precondition(reload.importGuest(into:"new-account"))
        reload.activateAccount("new-account"); precondition(reload.defaultNickname == "游客小星")
        precondition(TogetherPreferences.cleanNickname(String(repeating:"🌙",count:25)).count == 20)
        // Old schema-2 JSON without the optional map still decodes losslessly.
        var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as! [String:Any]
        legacy.removeValue(forKey:"defaultNicknames")
        let decodedLegacy = try JSONDecoder().decode(CompanionArchive.self,from:JSONSerialization.data(withJSONObject:legacy))
        precondition(decodedLegacy.defaultNicknames == nil)
        return "PASS: migration, retained memories, nickname precedence/clear, account isolation, guest adoption, cloud rollback and restart persistence"
    }
}
