import Foundation

@main struct ConversationGreetingTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value:Bool,_ message:String) { precondition(value,message); checks += 1 }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("starry-greeting-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("chat.json")
        let store = CompanionStore(storageURL:url)
        store.activateAccount("guest")
        let model = ModelDescriptor.miku
        let original = CharacterRecord(profile:model.collection.initialProfile())
        check(ConversationGreetingPolicy.shouldIntroduce(original),"An unmet role introduces itself")
        var profileOnly = original; profileOnly.profile.autoSpeak = false
        check(ConversationGreetingPolicy.shouldIntroduce(profileOnly),"Saved personal settings do not suppress the first introduction")
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
        let morning = Date(timeIntervalSince1970:8*3600)
        func context(_ reason:ConversationEntryReason,_ record:CharacterRecord,_ met:Bool = false,_ date:Date? = nil) -> ConversationGreetingContext {
            .make(reason:reason,record:record,hasMetAnyone:met,now:date ?? morning,calendar:calendar)
        }
        check(context(.appLaunch,original).scene == "firstLaunch","Fresh account launching has an introduction")
        check(context(.characterSelection,original).scene == "firstMeeting","Selecting a new role is a first meeting")
        check(context(.appLaunch,original,true).scene == "firstMeeting","An established account meeting a new role is not a new app user")
        let hello = store.dialogue.greeting(for:context(.appLaunch,original),record:original)
        check(hello.text.contains(model.name),"Greeting uses the actual character name")
        check(hello.eventName == "expression.request","Proactive greeting cannot request the full-body greeting cue")
        let entryID = UUID()
        store.update(model.id) {
            $0.messages.append(CompanionMessage(role:"assistant",text:hello.text,date:morning,proactiveScene:"firstLaunch"))
            $0.greeting = ConversationGreetingHistory(count:1,lastDate:morning,lastText:hello.text,lastEntryID:entryID)
        }
        check(store.guestTurns == 0,"Assistant messages do not consume the user's five turns")
        let restored = CompanionStore(storageURL:url); restored.activateAccount("guest")
        let met = restored.record(model.id)
        check(met.greeting?.lastEntryID == entryID && met.messages.first?.proactiveScene == "firstLaunch","Visit context survives storage")
        check(!ConversationGreetingPolicy.shouldIntroduce(met),"Persisted first greeting suppresses every later entry, including restart")
        check(context(.appLaunch,met,true).scene == "appLaunch","Restarting is a reunion, including assistant-only history")
        check(context(.conversationReturn,met,true).scene == "conversationReturn","Returning to a retained role has its own context")
        check(context(.characterSelection,met,true).scene == "characterSwitch","Selecting a known role is distinguished from first meeting")
        check(context(.foregroundReturn,met,true).scene == "foregroundReturn","Background return has its own context")
        check(store.dialogue.greeting(for:context(.appLaunch,met,true),record:met).text.contains("早上好"),"Local time changes launch greeting")
        check(store.dialogue.greeting(for:context(.appLaunch,met,true,Date(timeIntervalSince1970:20*3600)),record:met).text.contains("晚上好"),"Evening launch greeting")
        var old = CharacterRecord(profile:original.profile,messages:[CompanionMessage(role:"user",text:"今天有点累",date:morning)])
        let oldData = try JSONEncoder().encode(old)
        check(!String(decoding:oldData,as:UTF8.self).contains("greeting"),"Legacy shape has no required greeting metadata")
        let migrated = try JSONDecoder().decode(CharacterRecord.self,from:oldData)
        check(!ConversationGreetingPolicy.shouldIntroduce(migrated),"Legacy chat history without greeting metadata must not receive another introduction")
        check(context(.appLaunch,migrated,true).scene == "appLaunch" && context(.conversationReturn,migrated,true).hasUserMessages,"Old chat history counts as an existing relationship")
        check(context(.appLaunch,old,true,morning.addingTimeInterval(4*24*3600)).returningAfterDays,"Long absence uses actual recorded activity")
        old.messages.append(CompanionMessage(role:"user",text:"刚聊过",date:morning.addingTimeInterval(4*24*3600)))
        check(!context(.appLaunch,old,true,morning.addingTimeInterval(4*24*3600+1)).returningAfterDays,"Recent user activity overrides an older greeting")
        check(!context(.appLaunch,met,true,morning.addingTimeInterval(-500)).returningAfterDays,"Clock rollback cannot invent a long absence")
        var cleared = met; cleared.messages = []
        check(!ConversationGreetingPolicy.shouldIntroduce(cleared),"Clearing visible messages does not erase the persisted relationship")
        let assistantOnly = CharacterRecord(profile:original.profile,messages:[CompanionMessage(role:"assistant",text:"以前聊过")])
        check(!ConversationGreetingPolicy.shouldIntroduce(assistantOnly),"Old assistant-only journals also prevent duplicate greetings")
        for _ in 0..<8 {
            let newEntry = ConversationEntry(reason:.conversationReturn,characterID:model.id,accountID:"guest")
            check(newEntry.id != met.greeting?.lastEntryID && !ConversationGreetingPolicy.shouldIntroduce(met),"A fresh presentation UUID never resets a known relationship")
        }
        var customized = original; customized.profile.name = "小月"; customized.profile.personality = "活泼"
        customized.profile.tone = "温暖"
        let tailored = store.dialogue.greeting(for:context(.characterSelection,customized),record:customized).text
        check(tailored.contains("小月") && tailored.hasPrefix("嘿，") && tailored.contains("认真听"),"Custom name/personality/tone apply")
        restored.activateAccount(DemoAccount.alternateID)
        check(restored.record(model.id).greeting == nil && restored.record(model.id).messages.isEmpty,"Another account has no access to guest greetings")
        check(ConversationGreetingPolicy.shouldIntroduce(restored.record(model.id)),"Another account still gets its own first introduction")
        restored.activateAccount("guest")
        check(restored.record(ModelDescriptor.robot.id).greeting == nil,"Different roles do not inherit greetings")
        check(ConversationGreetingPolicy.shouldIntroduce(restored.record(ModelDescriptor.robot.id)),"A different role introduces itself independently")
        check(restored.importGuest(into:DemoAccount.id),"Newly logged-in account can keep its guest relationship")
        restored.activateAccount(DemoAccount.id)
        check(context(.conversationReturn,restored.record(model.id),true).scene == "conversationReturn","Login does not reintroduce an already met character")
        check(!ConversationGreetingPolicy.shouldIntroduce(restored.record(model.id)),"Guest-to-account adoption keeps the introduction consumed")
        print("PASS: \(checks) first-introduction policy, persistent deduplication, migration, account isolation and guest budget checks")
    }
}
