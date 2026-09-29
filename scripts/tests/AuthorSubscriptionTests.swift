import Foundation

@MainActor enum AuthorSubscriptionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func run() throws -> String {
        var checks = 0
        func check(_ pass: @autoclosure () -> Bool, _ message: String) throws {
            checks += 1; if !pass() { throw Failure(description: message) }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("author-core-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.json")
        let a = DemoAccount.id, b = DemoAccount.alternateID, miku = ModelDescriptor.miku.id, human = ModelDescriptor.human.id
        let privateRole = OwnedCharacter(id: "old-private", ownerID: a, baseID: human, profile: .init(name: "旧私有角色"), published: false, createdAt: Date(timeIntervalSince1970: 10))
        let publicRole = OwnedCharacter(id: "old-public", ownerID: a, baseID: human, profile: .init(name: "旧公开角色"), published: true, createdAt: Date(timeIntervalSince1970: 20))
        let legacy = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "accounts": [a: ["followed": [human,miku,miku,"removed-role"],"lastCharacter": human], b: ["followed": []]],
            "creations": try JSONSerialization.jsonObject(with: JSONEncoder().encode([privateRole,publicRole]))
        ], options: [.sortedKeys])
        try legacy.write(to: url)
        let library = CharacterLibrary(storageURL: url); library.activate(a, existing: [:])
        try check(library.archive.schemaVersion == 2, "Legacy archive migrated")
        try check(library.subscriptions == [human,miku,"removed-role"], "Order retained and duplicates removed")
        try check(library.followedAuthors.isEmpty && library.lastCharacter == human, "No inferred author follows; last retained")
        let backup = try Data(contentsOf: url.appendingPathExtension("v1.backup"))
        try check(backup == legacy, "Exact backup before migration")
        let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf:url)) as! [String:Any]
        let accounts = encoded["accounts"] as! [String:[String:Any]]
        try check(accounts[a]?["followed"] == nil && accounts[a]?["subscriptions"] != nil, "Only new relation keys encoded")
        let authorA = library.currentAuthor!
        try check(!authorA.id.contains(a) && authorA.id != AuthorProfile.starry.id, "Opaque public author identity")
        let publicAuthor = String(data: try JSONEncoder().encode(authorA), encoding:.utf8)!
        try check(!publicAuthor.contains(a) && !publicAuthor.contains("ownerID"), "Public author does not expose account join")
        try check(library.creation(privateRole.id)?.authorID == authorA.id && library.creation(publicRole.id)?.authorID == authorA.id, "Legacy creations get the same stable author")
        for model in ModelDescriptor.all { try check(library.author(for:model.id)?.id == AuthorProfile.starry.id, "Every builtin has a curator") }
        try check(library.publicWorks(by:authorA.id).map(\.id) == [publicRole.id], "Private role excluded even from own public page")
        let restored = CharacterLibrary(storageURL:url); restored.activate(a,existing:[:])
        try check(restored.currentAuthor?.id == authorA.id, "Author stable across relaunch")
        let order = restored.subscriptions
        try check(restored.subscribe(human,true) && restored.subscriptions == order, "Subscribe idempotent, no reorder")
        try check(restored.followAuthor(AuthorProfile.starry.id,true), "Follow author succeeds")
        try check(restored.followAuthor(AuthorProfile.starry.id,true) && restored.followedAuthors.count == 1, "Follow idempotent")
        try check(restored.subscriptions == order, "Following author cannot subscribe its other roles")
        try check(restored.subscribe(miku,false) && restored.followedAuthors.count == 1, "Unsubscribe keeps author follow")
        let subBeforeUnfollow = restored.subscriptions
        try check(restored.followAuthor(AuthorProfile.starry.id,false) && restored.subscriptions == subBeforeUnfollow, "Unfollow keeps subscriptions")
        try check(!restored.followAuthor(authorA.id,true), "Cannot follow self")
        try check(!restored.subscribe("unknown",true), "Cannot subscribe unavailable role")
        try check(restored.subscribe("removed-role",false) && !restored.subscriptions.contains("removed-role"), "Unavailable subscription removable")
        restored.activate(b,existing:[:])
        try check(restored.subscriptions.isEmpty && restored.lastCharacter == nil, "Explicit empty migration never seeds default")
        try check(restored.followedAuthors.isEmpty, "Author relations account isolated")
        try check(restored.model(privateRole.id) == nil && restored.author(for:privateRole.id) == nil && restored.publishedProfile(privateRole.id) == nil, "Known private IDs do not bypass visibility")
        try check(restored.followAuthor(authorA.id,true), "Second identity can follow public creator")
        try check(restored.subscriptions.isEmpty, "Author follow leaves empty character subscriptions")
        try check(restored.followedAuthorWorks.map(\.id) == [publicRole.id], "Following-author feed is public works only")
        try check(restored.followers(of:authorA.id).map(\.id) == [restored.currentAuthor!.id], "Local follower count/list matches actual relation")
        var hacked = authorA; hacked.name = "错误的跨账号改名"
        try check(!restored.updateAuthor(hacked) && restored.author(authorA.id)?.name == authorA.name, "Cross-account author editing denied")
        try check(!restored.publish(publicRole.id,value:false,profile:publicRole.profile), "Cross-account publication denied")
        try check(restored.select(publicRole.id), "Entering a role explicitly subscribes it")
        try check(restored.subscriptions == [publicRole.id] && restored.lastCharacter == publicRole.id, "Entering persists subscription and last role")
        restored.activate(a,existing:[:])
        var edited = restored.currentAuthor!; edited.name = "月光作者"; edited.bio = "喜欢海风与安静的故事"; edited.avatar = "leaf"
        try check(restored.updateAuthor(edited), "Own public profile editable")
        try check(restored.author(for:publicRole.id)?.name == "月光作者", "Existing works resolve latest author identity")
        let revision = restored.currentAuthor!.revision
        try check(restored.updateAuthor(edited) && restored.currentAuthor!.revision == revision, "No-op save does not manufacture revision")
        var empty = edited; empty.name = "  \n"
        try check(!restored.updateAuthor(empty) && restored.currentAuthor!.name == "月光作者", "Empty name rejected without mutation")
        try check(restored.currentAuthor!.matches("月光 海风"), "Author search requires all words across profile")
        try check(!restored.currentAuthor!.matches("不存在"), "Author search rejects unrelated text")
        try check(restored.publish(publicRole.id,value:false,profile:publicRole.profile), "Owner withdraws")
        restored.activate(b,existing:[:])
        try check(restored.model(publicRole.id) == nil && restored.publicWorks(by:authorA.id).isEmpty && restored.followedAuthorWorks.isEmpty, "Withdrawn work hidden from all public paths")
        try check(restored.subscriptions == [publicRole.id] && restored.availableSubscriptions.isEmpty && restored.lastCharacter == nil, "Unavailable subscription retained without invalid resume")
        try check(restored.followedAuthors == [authorA.id], "Withdrawal does not unfollow author")
        restored.activate(a,existing:[:]); try check(restored.publish(publicRole.id,value:true,profile:publicRole.profile), "Republish succeeds")
        restored.activate(b,existing:[:]); try check(restored.availableSubscriptions.map(\.id) == [publicRole.id], "Existing subscription resolves after republish")
        try check(restored.author(for:publicRole.id)?.id == authorA.id, "Publication preserves creator identity")
        let own = restored.create(base:.robot,profile:.init(name:"B 的新角色"),published:true)!
        try check(restored.author(for:own)?.id == restored.currentAuthor?.id && restored.author(for:own)?.id != authorA.id, "Creation derives owner author, not base author")
        let ownAuthor = restored.currentAuthor!.id
        restored.activate(a,existing:[:])
        try check(restored.discoverAuthors.contains { $0.id == ownAuthor }, "Published creator discoverable")
        try check(CharacterSearch.matches("月光",model:ModelDescriptor.human,profile:publicRole.profile,authorName:edited.name), "Role search includes author name")
        let fresh = CharacterLibrary(storageURL:folder.appendingPathComponent("fresh.json")); fresh.activate("guest",existing:[:])
        try check(fresh.subscriptions == [miku] && fresh.followedAuthors.isEmpty && fresh.currentAuthor == nil, "New guest starts with one role, no creator follows")
        try check(fresh.create(base:.robot,profile:.init(name:"禁止匿名创建"),published:true) == nil, "Anonymous creation blocked in repository")
        fresh.subscribe(miku,false); fresh.select(human); fresh.followAuthor(AuthorProfile.starry.id,true)
        fresh.activate(a,existing:[:],adoptingGuest:true)
        try check(fresh.subscriptions == [human] && fresh.followedAuthors == [AuthorProfile.starry.id] && fresh.lastCharacter == human, "New login adopts both guest relations")
        fresh.activate(b,existing:[:],adoptingGuest:true)
        try check(fresh.subscriptions == [miku] && fresh.followedAuthors.isEmpty, "No guest adoption by second identity")
        fresh.subscribe(miku,false); fresh.activate(a,existing:[:]); fresh.activate(b,existing:[:],adoptingGuest:true)
        try check(fresh.subscriptions.isEmpty, "Returning identity keeps intentional empty subscriptions")
        let blankGuest = CharacterLibrary(storageURL:folder.appendingPathComponent("blank-guest.json"))
        blankGuest.activate("guest",existing:[:]); blankGuest.subscribe(miku,false); blankGuest.activate(a,existing:[:],adoptingGuest:true)
        try check(blankGuest.subscriptions.isEmpty, "Explicit guest empty choice adopted without reseeding")
        let roundtrip = CharacterLibrary(storageURL:folder.appendingPathComponent("fresh.json")); roundtrip.activate(a,existing:[:])
        try check(roundtrip.subscriptions == [human] && roundtrip.followedAuthors == [AuthorProfile.starry.id], "Relations survive disk restore")
        let futureURL = folder.appendingPathComponent("future.json"), future = Data("{\"schemaVersion\":99,\"accounts\":{},\"creations\":[]}".utf8)
        try future.write(to:futureURL)
        let unknown = CharacterLibrary(storageURL:futureURL); unknown.activate(a,existing:[:])
        try check(unknown.error != nil && !unknown.followAuthor(AuthorProfile.starry.id,true) && !unknown.subscribe(human,true), "Future schema blocks every new mutation")
        let futureAfter = try Data(contentsOf:futureURL); try check(futureAfter == future, "Future file remains byte-identical")
        let blocker = folder.appendingPathComponent("not-a-directory"); try Data("block".utf8).write(to:blocker)
        let failed = CharacterLibrary(storageURL:blocker.appendingPathComponent("state.json")); failed.activate(a,existing:[:])
        try check(failed.archive.accounts.isEmpty && failed.archive.authors.isEmpty && failed.error != nil, "Failed persistence publishes no partial author/account")
        try check(!failed.followAuthor(AuthorProfile.starry.id,true) && failed.followedAuthors.isEmpty, "Failed follow leaves UI state unchanged")
        return "PASS: \(checks) author/subscription checks · migration, ownership, visibility, independence, handoff, persistence"
    }
}
