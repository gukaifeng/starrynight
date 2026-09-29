import Foundation

@MainActor enum MarketplaceCoreTests {
    struct Failure: Error, CustomStringConvertible { let description:String }
    static func run() throws -> String {
        var count = 0
        func check(_ condition:Bool,_ message:String) throws {
            guard condition else { throw Failure(description:message) }; count += 1
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("market-check-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let libraryURL = directory.appendingPathComponent("library.json"), chatURL = directory.appendingPathComponent("chat.json")
        let base = ModelDescriptor.defaultCharacter, a = DemoAccount.id, b = DemoAccount.alternateID
        let library = CharacterLibrary(storageURL:libraryURL)
        library.activate(a,existing:[:])
        let chat = CompanionStore(storageURL:chatURL,arguments:[])
        chat.activateAccount(a)
        let message = CompanionMessage(role:"user",text:"聊天记录必须保留",source:"cloud-v1")
        chat.update(base.id) { $0.messages.append(message); $0.memories.append(CompanionMemory(text:"记忆也保留")) }
        let chatBefore = try Data(contentsOf:chatURL)
        try check(library.hideConversation(base.id,latestMessage:message.date),"Hide persists")
        try check(library.isConversationHidden(base.id,latestMessage:message.date),"Old messages remain hidden")
        try check(library.subscriptions.contains(base.id) && library.lastCharacter == base.id,"Hide does not unsubscribe or change current role")
        try check(try Data(contentsOf:chatURL) == chatBefore,"Hide never writes or deletes the transcript, memories or profile")
        try check(ConversationSearch.find("必须保留",records:chat.currentRecords,visibleIDs:[base.id]).count == 1,"Hidden conversations remain searchable")
        let reloaded = CharacterLibrary(storageURL:libraryURL); reloaded.activate(a,existing:chat.currentRecords)
        try check(reloaded.isConversationHidden(base.id,latestMessage:message.date),"Hidden state survives restart")
        try check(reloaded.select(base.id,showInMessages:false) && reloaded.isConversationHidden(base.id),"Automatic home restoration does not clear hidden state")
        reloaded.activate(b,existing:[:])
        try check(!reloaded.isConversationHidden(base.id),"Hidden state cannot leak between accounts")
        reloaded.activate(a,existing:[:])
        try check(reloaded.isConversationHidden(base.id),"Switching back restores the account visibility state")
        try check(!reloaded.isConversationHidden(base.id,latestMessage:Date().addingTimeInterval(60)),"A newer incoming message makes the conversation visible")
        try check(reloaded.select(base.id) && !reloaded.isConversationHidden(base.id),"Explicit conversation entry restores visibility")
        reloaded.hideConversation(base.id)
        try check(reloaded.restoreConversation(base.id) && !reloaded.isConversationHidden(base.id),"Manual restore is reversible")
        let old = try JSONDecoder().decode(CharacterLibraryAccount.self,from:Data("{\"subscriptions\":[]}".utf8))
        try check(old.hiddenConversations.isEmpty,"Pre-feature archives decode without hidden metadata")

        let privateID = reloaded.create(base:base,profile:CharacterProfile(name:"私人草稿"),published:false)!
        let publicID = reloaded.create(base:base,profile:CharacterProfile(name:"公开月光伙伴"),published:true)!
        let ownCatalog = CharacterMarketplace.localCatalog(reloaded)
        try check(!ownCatalog.contains { $0.id == privateID },"Even one's own private draft is excluded from the market")
        try check(ownCatalog.contains { $0.id == publicID },"Published creator works appear")
        reloaded.activate(b,existing:[:])
        let catalog = CharacterMarketplace.localCatalog(reloaded)
        try check(reloaded.model(privateID) == nil && !catalog.contains { $0.id == privateID },"Another account cannot access a private role")
        try check(catalog.contains { $0.id == publicID },"Public listings are visible across local accounts")
        func results(_ query:MarketQuery) -> [CharacterMarketItem] {
            CharacterMarketplace.results(catalog,query:query,subscriptions:Set(reloaded.subscriptions),followedAuthors:Set(reloaded.followedAuthors))
        }
        var query = MarketQuery(); query.text = "  公开 月光  "
        try check(results(query).map(\.id) == [publicID],"Search trims spaces and matches all terms")
        query = MarketQuery(); query.shelf = .creators
        try check(results(query).map(\.id) == [publicID],"Creator shelf excludes builtin listings")
        query = MarketQuery(); query.category = "治愈"
        try check(!results(query).isEmpty && results(query).allSatisfy { $0.categories.contains("治愈") },"Category filter uses authored listing tags")
        query = MarketQuery(); query.subscribedOnly = true
        try check(results(query).map(\.id) == [base.id],"Subscriptions filter is account-scoped")
        query = MarketQuery(); query.followedAuthorsOnly = true
        try check(results(query).isEmpty,"Unfollowed authors don't pass the filter")
        let author = reloaded.author(for:publicID)!
        try check(reloaded.followAuthor(author.id,true),"Follow the creator")
        try check(results(query).map(\.id) == [publicID],"Creator follow exposes exactly that author's public listing")
        query = MarketQuery(); query.sort = .updated
        try check(results(query).first?.id == publicID,"Recently published work sorts before undated builtin catalog")
        query.sort = .name
        try check(results(query).map(\.profile.name) == catalog.map(\.profile.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending },"Name order is stable and localized")
        query.text = "不存在的搜寻词"
        try check(results(query).isEmpty,"No-result search doesn't silently show unrelated recommendations")
        reloaded.activate(a,existing:[:]); reloaded.publish(publicID,value:false,profile:CharacterProfile(name:"公开月光伙伴"))
        try check(!CharacterMarketplace.localCatalog(reloaded).contains { $0.id == publicID },"Unpublishing removes the listing immediately")
        return "PASS: Marketplace / hidden conversations · \(count) checks"
    }
}
