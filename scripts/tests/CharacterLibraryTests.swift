import Foundation

#if !os(iOS)
@main
#endif
struct CharacterLibraryTests {
    @MainActor static func main() throws { print(try run()) }
    @MainActor static func run() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("starry-library-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("library.json"), chatURL = folder.appendingPathComponent("chat.json")
        var checks = 0
        func check(_ pass:Bool,_ message:String) { precondition(pass,message); checks += 1 }
        let library = CharacterLibrary(storageURL:url)
        library.activate(DemoAccount.id,existing:[:])
        check(library.subscriptions == [ModelDescriptor.defaultCharacter.id],"A new account follows exactly one default")
        library.subscribe(ModelDescriptor.defaultCharacter.id,false)
        let restored = CharacterLibrary(storageURL:url); restored.activate(DemoAccount.id,existing:[:])
        check(restored.subscriptions.isEmpty && restored.lastCharacter == nil,"Explicit empty follows survives restore")
        var profile = CharacterProfile(name:"自建角色一");profile.studio = CharacterStudio()
        let first = restored.create(base:ModelDescriptor.all[1],profile:profile,published:false)!
        profile.name = "自建角色二"
        let second = restored.create(base:ModelDescriptor.all[1],profile:profile,published:true)!
        check(first != second && restored.model(first)?.runtimeID == ModelDescriptor.all[1].id && restored.model(second)?.runtimeID == ModelDescriptor.all[1].id,"Unique instance IDs share one runtime base")
        let chat = CompanionStore(storageURL:chatURL)
        chat.saveProfile(restored.publishedProfile(first)!,id:first)
        chat.update(first) { $0.messages.append(CompanionMessage(role:"user",text:"私有的对话"));$0.memories.append(CompanionMemory(text:"私有的记忆")) }
        chat.saveProfile(profile,id:second)
        check(chat.record(second).messages.isEmpty && chat.record(second).memories.isEmpty,"Sibling instances cannot share chats or memory")
        restored.activate(DemoAccount.alternateID,existing:[:]);chat.activateAccount(DemoAccount.alternateID)
        check(restored.model(first) == nil && restored.publishedProfile(first) == nil,"Private IDs are denied even when known")
        check(restored.discover.contains { $0.id == second },"Another identity discovers published snapshots")
        check(chat.record(first).messages.isEmpty && chat.record(first).memories.isEmpty,"Account namespace protects messages and memories")
        restored.select(second)
        chat.saveProfile(restored.publishedProfile(second)!,id:second)
        var changed = chat.record(second).profile;changed.name = "B自己的昵称";chat.saveProfile(changed,id:second)
        restored.activate(DemoAccount.id,existing:[:]);chat.activateAccount(DemoAccount.id)
        check(chat.record(second).profile.name == "自建角色二","Consumer customizations do not rewrite creator settings")
        check(chat.record(first).messages.count == 1 && chat.record(first).memories.count == 1,"Creator private records remain intact")
        check(restored.lastCharacter == second,"Last character is scoped to creator")
        restored.publish(second,value:false,profile:profile)
        restored.activate(DemoAccount.alternateID,existing:[:])
        check(restored.model(second) == nil && restored.lastCharacter == ModelDescriptor.defaultCharacter.id,"Withdrawing publication prevents resolution and falls back safely")
        let again = CharacterLibrary(storageURL:url);again.activate(DemoAccount.id,existing:[:])
        check(again.creations.count == 2 && again.subscriptions.contains(first),"Creations and follows survive disk restore")
        let data = try String(contentsOf:url,encoding:.utf8)
        check(!data.contains("私有的对话") && !data.contains("私有的记忆"),"Published directory never serializes chat or memory")
        var old = CharacterRecord(profile:.initial(ModelDescriptor.all[1].id)); old.messages.append(CompanionMessage(role:"user",text:"已有聊天"))
        let migration = CharacterLibrary(storageURL:folder.appendingPathComponent("migrate.json"))
        migration.activate(DemoAccount.id,existing:[ModelDescriptor.all[1].id:old])
        check(migration.lastCharacter == ModelDescriptor.all[1].id && migration.subscriptions == [ModelDescriptor.all[1].id],"Existing chats migrate into follows without rewriting chat storage")
        let futureURL = folder.appendingPathComponent("future.json"), future = Data("{\"schemaVersion\":99,\"accounts\":{},\"creations\":[]}".utf8)
        try future.write(to:futureURL)
        let futureStore = CharacterLibrary(storageURL:futureURL);futureStore.activate(DemoAccount.id,existing:[:])
        check(futureStore.error != nil && !futureStore.subscribe(ModelDescriptor.all[1].id,true),"Unsupported schema blocks writes")
        check(try Data(contentsOf:futureURL) == future,"Unsupported future archive is preserved exactly")
        // Collection allowlists and private instance settings are exercised as real records.
        let miku = ModelDescriptor.defaultCharacter, human = ModelDescriptor.all[1]
        for model in ModelDescriptor.all {
            check(model.collection.isCompatible(with:model),"Every built-in collection is compatible")
            check(model.collection.availableEnvironments.map(\.id) == model.collection.environments,"Only declared scenes resolve")
        }
        var foreign = human.collection.initialProfile()
        foreign.audio = CharacterAudioPreferences(enabled:true,trackID:human.collection.defaultMusic,volume:0.17)
        foreign.voiceID = human.collection.defaultVoice
        foreign.studio?.selectEnvironment("seaside")
        let normalized = miku.collection.normalize(foreign)
        check(normalized.resolvedStudio.room == miku.collection.defaultEnvironment,"Foreign background falls back to collection default")
        check(normalized.voiceID == miku.collection.defaultVoice && normalized.audio?.trackID == miku.collection.defaultMusic,"Foreign voice and track cannot escape allowlists")
        check(normalized.resolvedStudio.environments?["seaside"] == nil,"Foreign scene tuning is not retained")
        check(restored.archive.creations.first?.collection != nil,"New creations own a collection snapshot")
        chat.saveProfile(foreign,id:first)
        var sibling = human.collection.initialProfile();sibling.audio?.enabled = false;sibling.autoSpeak = false
        chat.saveProfile(sibling,id:second)
        check(chat.record(first).profile.audio?.volume == 0.17 && chat.record(second).profile.audio?.enabled == false,"Sibling music and volume are independent")
        check(chat.record(first).profile.autoSpeak && !chat.record(second).profile.autoSpeak,"Voice mute is character-scoped")
        chat.activateAccount(DemoAccount.alternateID)
        check(chat.record(first).profile.audio == nil,"Other accounts cannot read music settings")
        check(CharacterSearch.matches("  "+foreign.name+"   ",model:human,profile:foreign),"Search includes personality and trims spaces")
        check(CharacterSearch.matches(miku.originalName.uppercased(),model:miku,profile:miku.collection.initialProfile()),"Search matches original names ignoring case")
        check(!CharacterSearch.matches("不存在的角色",model:human,profile:foreign),"Search rejects unrelated text")
        let guestURL = folder.appendingPathComponent("guest.json")
        let guest = CompanionStore(storageURL:guestURL);guest.activateAccount("guest")
        guest.saveProfile(miku.collection.initialProfile(),id:miku.id)
        for round in 1...5 {
            guest.update(round % 2 == 0 ? human.id : miku.id,countGuestTurn:true) { $0.messages.append(CompanionMessage(role:"user",text:"第\(round)轮")) }
        }
        check(guest.guestLimitReached && guest.guestTurns == 5,"Five turns share one guest budget across roles")
        guest.update(miku.id,countGuestTurn:true) { $0.messages.append(CompanionMessage(role:"user",text:"第六轮不可写")) }
        check(guest.guestTurns == 5 && guest.record(miku.id).messages.count == 3,"Sixth user message is rejected before storage")
        guest.update(miku.id) { $0.messages.removeAll() }
        let guestRestored = CompanionStore(storageURL:guestURL);guestRestored.activateAccount("guest")
        check(guestRestored.guestLimitReached,"Clearing history and relaunch cannot reset the allowance")
        check(guestRestored.importGuest(into:DemoAccount.id),"New account can adopt guest records")
        guestRestored.activateAccount(DemoAccount.id)
        check(guestRestored.record(human.id).messages.count == 2,"Guest handoff preserves messages")
        check(!guestRestored.importGuest(into:DemoAccount.alternateID),"Guest data is never copied into a second identity")
        let compatible = try JSONDecoder().decode(CharacterProfile.self,from:JSONSerialization.data(withJSONObject:["name":"旧角色","background":"以前","personality":"温柔","tone":"自然","concise":false,"accent":"玉青","ambience":"晨光","autoSpeak":true,"voiceSpeed":1]))
        check(compatible.audio == nil && compatible.voiceID == nil,"Pre-collection profiles remain decodable")
        let older = CompanionMessage(role:"user",text:"在海边一起看月亮 🌙 Café ＡＩ",date:Date(timeIntervalSince1970:1))
        let newer = CompanionMessage(role:"assistant",text:"一起看月亮吧",date:Date(timeIntervalSince1970:2))
        let searchRecords = ["visible":CharacterRecord(profile:CharacterProfile(name:"只有角色名"),messages:[older,newer]),
                             "private":CharacterRecord(profile:CharacterProfile(name:"别人"),messages:[newer])]
        let hits = ConversationSearch.find("月亮",records:searchRecords,visibleIDs:["visible"])
        check(hits.count == 2 && hits[0].message.id == newer.id,"Search finds both senders and sorts by message date")
        check(hits.allSatisfy { $0.characterID == "visible" },"Unavailable private roles never appear")
        check(ConversationSearch.find("只有角色名",records:searchRecords,visibleIDs:["visible"]).isEmpty,"Search uses message text, not a character name")
        check(ConversationSearch.find("cafe ai",records:searchRecords,visibleIDs:["visible"]).count == 1,"Search folds accents, width and case with all query words")
        check(ConversationSearch.find("  ",records:searchRecords,visibleIDs:["visible"]).isEmpty,"Blank query is not a full archive dump")
        check(ConversationSearch.find("🌙",records:searchRecords,visibleIDs:["visible"]).first?.excerpt.contains("🌙") == true,"Unicode excerpts preserve emoji")
        let longText = String(repeating:"前文",count:100)+"独特关键字"+String(repeating:"后文",count:100)
        let longHits = ConversationSearch.find("独特关键字",records:["visible":CharacterRecord(profile:.initial("visible"),messages:[CompanionMessage(role:"user",text:longText)])],visibleIDs:["visible"])
        check(longHits.first?.excerpt.contains("独特关键字") == true && longHits[0].excerpt.count < 100,"Excerpt centers the match, even deep inside a long message")
        let history = [older] + (0..<200).map { CompanionMessage(role:"user",text:"历史消息 \($0)") }
        check(!ConversationSearch.window(history,around:nil).contains { $0.id == older.id },"Normal viewport remains bounded to recent messages")
        check(ConversationSearch.window(history,around:older.id).first?.id == older.id,"Search can open a message older than the normal viewport")
        check(ConversationSearch.window(history,around:history[100].id).count == 60 && ConversationSearch.window(history,around:history[100].id).contains { $0.id == history[100].id },"Focused history remains a bounded window around its target")
        check(ConversationSearch.window(history,around:UUID()).last?.id == history.last?.id,"Missing search targets safely fall back to latest")
        check(ConversationSearch.find("私有的对话",records:chat.currentRecords,visibleIDs:[first,second]).isEmpty,"Searching current identity cannot reveal a different account's stored text")
        checks += try verifyAuthoredDefinitions()
        checks += try verifyMusicAutoplay()
        try verifyGlobalChatDisplay()
        return "PASS: \(checks) collection, guest budget, search, identity, privacy, migration and persistence checks; authored definitions, isolated music and global chat font migration"
    }
    @MainActor private static func verifyMusicAutoplay() throws -> Int {
        var checks = 0
        func check(_ result:Bool,_ message:String) { precondition(result,message); checks += 1 }
        for model in ModelDescriptor.all {
            let initial = model.conversationProfile(preserving:nil).audio!
            check(initial.enabled && initial.trackID == model.collection.defaultMusic,"Every new character conversation defaults to its own music")
            check(initial.autoplayVersion == 1,"New preferences preserve an explicit playback policy")
        }
        let model = ModelDescriptor.defaultCharacter
        let legacyData = try JSONSerialization.data(withJSONObject:["enabled":false,"trackID":model.collection.music.last!.id,"volume":0.17])
        let legacy = try JSONDecoder().decode(CharacterAudioPreferences.self,from:legacyData)
        check(legacy.autoplayVersion == nil && !legacy.enabled,"Old archives remain readable without a required new field")
        var profile = model.collection.initialProfile(); profile.audio = legacy
        let migrated = model.conversationProfile(preserving:profile).audio!
        check(migrated.enabled && migrated.autoplayVersion == 1,"Old default-off preferences upgrade to autoplay")
        check(migrated.trackID == legacy.trackID && migrated.volume == legacy.volume,"Autoplay migration retains the chosen track and volume")
        var paused = migrated; paused.volume = 0
        let restored = try JSONDecoder().decode(CharacterAudioPreferences.self,from:JSONEncoder().encode(paused))
        profile.audio = restored
        check(model.conversationProfile(preserving:profile).audio!.volume == 0,"A current zero-volume choice survives normalization")
        check(restored.normalizedAutoplay == restored,"Autoplay normalization cannot repeatedly re-enable a paused role")
        check(ModelDescriptor.all[2].conversationProfile(preserving:nil).audio!.enabled,"A paused role does not disable a new role's default music")
        return checks
    }
    @MainActor private static func verifyAuthoredDefinitions() throws -> Int {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("starry-authored-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        var checks = 0
        func check(_ result:Bool,_ message:String) { precondition(result,message); checks += 1 }
        let library = CharacterLibrary(storageURL:folder.appendingPathComponent("library.json"))
        library.activate(DemoAccount.id,existing:[:])
        let base = ModelDescriptor.all[1]
        var definition = base.collection.initialProfile()
        definition.name = "写好的角色"
        definition.background = "作者设定的故事"
        definition.personality = "沉静"; definition.tone = "轻柔"; definition.concise = true
        definition.voiceSpeed = 0.91; definition.voiceID = base.collection.voices.last!.id
        definition.framing = CharacterFraming(shot:"conversation",size:1.02,angle:5)
        var studio = definition.resolvedStudio
        studio.selectEnvironment("garden"); studio.faceWidth = 0.37; studio.lightAngle = 24
        definition.studio = studio
        let first = library.create(base:base,profile:definition,published:true)!
        let second = library.create(base:base,profile:definition,published:false)!
        let model = library.model(first)!, sibling = library.model(second)!
        let authored = library.publishedProfile(first)!
        check(model.authoredProfileSnapshot == authored,"An instance carries its complete authored definition")
        check(model.collection.optionScope == first && sibling.collection.optionScope == second,"Each creation owns an option namespace")
        check(model.collection.isCompatible(with:model) && sibling.collection.isCompatible(with:sibling),"Scoped authored collections remain compatible")
        check(Set(model.collection.voices.map(\.id)).isDisjoint(with:sibling.collection.voices.map(\.id)),"Sibling voice selections have distinct IDs")
        check(Set(model.collection.music.map(\.id)).isDisjoint(with:sibling.collection.music.map(\.id)),"Sibling music selections have distinct IDs")

        var attempted = authored
        attempted.name = "不应覆盖的名字"; attempted.background = "不应覆盖的故事"
        attempted.personality = "活泼"; attempted.tone = "热烈"; attempted.concise = false
        attempted.voiceSpeed = 1.4; attempted.voiceID = model.collection.voices.first!.id
        attempted.framing = CharacterFraming(shot:"full",size:0.9,angle:-20)
        var changedStudio = authored.resolvedStudio
        changedStudio.selectEnvironment("seaside"); changedStudio.faceWidth = 0.92
        attempted.studio = changedStudio
        attempted.autoSpeak = false
        attempted.audio = CharacterAudioPreferences(enabled:true,trackID:model.collection.music.last!.id,volume:0.16)
        let conversation = model.conversationProfile(preserving:attempted)
        check(conversation.name == authored.name && conversation.background == authored.background,"Conversation keeps the authored identity and story")
        check(conversation.personality == authored.personality && conversation.tone == authored.tone && conversation.concise == authored.concise,"Conversation keeps the authored personality")
        check(conversation.voiceID == authored.voiceID && conversation.voiceSpeed == authored.voiceSpeed,"Listener preferences cannot replace the authored voice")
        check(conversation.resolvedStudio == authored.resolvedStudio && conversation.resolvedFraming == authored.resolvedFraming,"Appearance, stage and camera remain authored")
        check(conversation.autoSpeak && conversation.audio?.speechVolume == 0 && conversation.audio?.volume == attempted.audio?.volume,"Legacy voice mute becomes personal zero speech volume")
        check(model.conversationProfile(preserving:nil).autoSpeak,"A new listener starts with speech playback enabled")

        check(library.publish(first,value:true,profile:attempted),"Repeated publication remains valid")
        check(library.publishedProfile(first) == authored,"Publishing an already-public role cannot rewrite its definition")
        check(library.publish(first,value:false,profile:attempted) && library.publish(first,value:true,profile:attempted),"Withdrawal and republication remain available")
        check(library.publishedProfile(first) == authored,"Visibility changes cannot replace the definition")
        let restored = CharacterLibrary(storageURL:folder.appendingPathComponent("library.json"))
        restored.activate(DemoAccount.alternateID,existing:[:])
        check(restored.model(first)?.conversationProfile(preserving:attempted).name == authored.name,"Another account sees the same authored role after reload")
        check(restored.model(second) == nil,"Private sibling definitions remain private")

        var legacySelection = authored
        legacySelection.voiceID = base.collection.voices.last!.id
        legacySelection.audio = CharacterAudioPreferences(enabled:true,trackID:base.collection.music.last!.id,volume:0.16)
        let migrated = model.collection.normalize(legacySelection)
        check(migrated.voiceID == model.collection.voices.last!.id && migrated.audio?.trackID == model.collection.music.last!.id,"Legacy base-prefixed choices migrate only into their own instance")
        var foreignSelection = conversation
        foreignSelection.voiceID = sibling.collection.voices.last!.id
        foreignSelection.audio?.trackID = sibling.collection.music.last!.id
        let rejected = model.collection.normalize(foreignSelection)
        check(rejected.voiceID == model.collection.defaultVoice && rejected.audio?.trackID == model.collection.defaultMusic,"Sibling selections cannot cross the collection boundary")

        var assets = Set<String>(), fingerprints = Set<String>()
        for builtin in ModelDescriptor.all {
            let collection = builtin.collection
            check(collection.music.count == 1,"Every built-in role has exactly one authored theme")
            for track in collection.music {
                check(track.sourceModelID == builtin.runtimeID,"A track declares the role whose music it belongs to")
                check(track.id.hasPrefix(builtin.id+"/"),"Built-in track IDs stay role-scoped")
                check(assets.insert(track.asset).inserted,"Different base roles cannot silently point to the same audio asset")
                check(track.sha256?.count == 64 && fingerprints.insert(track.sha256 ?? "").inserted,"Each shipped composition has its own source fingerprint")
            }
        }
        check(model.collection.music.map(\.asset) == base.collection.music.map(\.asset),"Sibling instances may reuse immutable source files while their option IDs remain isolated")
        return checks
    }
    @MainActor private static func verifyGlobalChatDisplay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("starry-display-"+UUID().uuidString)
        let suite = "starry-display-check-"+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        let normalBefore = UserDefaults.standard.object(forKey:ChatDisplaySettings.fontPreferenceKey) as? NSNumber
        defer {
            defaults.removePersistentDomain(forName:suite)
            try? FileManager.default.removeItem(at:folder)
        }
        var archive = CompanionArchive()
        archive.chatDisplay = ChatDisplaySettings(heightFraction:0.35,fontSize:24)
        var record = CharacterRecord(profile:.initial("hatsune-miku"))
        record.messages.append(CompanionMessage(role:"user",text:"升级前的聊天"))
        archive.characters["hatsune-miku"] = record
        let url = folder.appendingPathComponent("old-chat.json")
        try CompanionPersistence.write(archive,to:url)

        let first = CompanionStore(storageURL:url,displayDefaults:defaults,arguments:[])
        precondition(first.chatDisplay == ChatDisplaySettings(heightFraction:0.60,fontSize:15),"Old journal settings must not replace the new global default")
        precondition(first.record("hatsune-miku").messages.first?.text == "升级前的聊天")
        precondition(first.archive.chatDisplay == archive.chatDisplay,"Reading an older archive remains lossless")
        first.chatDisplay = ChatDisplaySettings(heightFraction:0.70,fontSize:22)
        precondition(first.saveChatDisplay())
        precondition(first.chatDisplay == ChatDisplaySettings(heightFraction:0.60,fontSize:22))
        for account in ["guest",DemoAccount.alternateID,DemoAccount.id] {
            first.activateAccount(account)
            precondition(first.chatDisplay.fontSize == 22,"Account changes cannot restore an old font")
        }
        let restarted = CompanionStore(storageURL:url,displayDefaults:defaults,arguments:[])
        precondition(restarted.chatDisplay.fontSize == 22,"Global font survives relaunch despite old archive display values")
        precondition(restarted.archive.chatDisplay?.fontSize == 24,"Font changes must not write back into a journal")
        let another = CompanionStore(storageURL:folder.appendingPathComponent("another-chat.json"),displayDefaults:defaults,arguments:[])
        precondition(another.chatDisplay.fontSize == 22,"The device preference is independent of the journal")
        restarted.chatDisplay = ChatDisplaySettings(); precondition(restarted.saveChatDisplay())
        precondition(ChatDisplaySettings.load(from:defaults).fontSize == 15)
        defaults.set(Double.infinity,forKey:ChatDisplaySettings.fontPreferenceKey)
        precondition(ChatDisplaySettings.load(from:defaults) == ChatDisplaySettings())
        defaults.set(2,forKey:ChatDisplaySettings.fontPreferenceKey)
        precondition(ChatDisplaySettings.load(from:defaults).fontSize == 14)

        let fixtureURL = folder.appendingPathComponent("isolated-chat.json")
        let fixtureSuite = ChatDisplaySettings.fixturePreferenceSuite(for:fixtureURL)
        defer { UserDefaults(suiteName:fixtureSuite)?.removePersistentDomain(forName:fixtureSuite) }
        let fixture = CompanionStore(storageURL:fixtureURL,arguments:[])
        precondition(fixture.chatDisplay.fontSize == 15)
        fixture.chatDisplay.fontSize = 20; precondition(fixture.saveChatDisplay())
        precondition(CompanionStore(storageURL:fixtureURL,arguments:[]).chatDisplay.fontSize == 20)
        precondition(UserDefaults.standard.object(forKey:ChatDisplaySettings.fontPreferenceKey) as? NSNumber == normalBefore,
                     "Fixture font settings must never modify normal app preferences")

    }
}
