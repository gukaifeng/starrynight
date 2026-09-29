import Foundation
import Observation

/// Local social repository. Role subscriptions and creator follows are separate
/// account-scoped relations. Visibility is enforced here, not only in views.
@MainActor @Observable
final class CharacterLibrary {
    private(set) var archive = CharacterLibraryArchive()
    var error: String?
    private(set) var accountID = DemoAccount.id
    @ObservationIgnored private var blocked = false
    @ObservationIgnored private let url: URL
    init(storageURL: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--companion-testing")
        url = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(testing ? "character-library-test.json" : "character-library.json")
        if testing && storageURL == nil && !ProcessInfo.processInfo.arguments.contains("--keep-companion-data") { try? FileManager.default.removeItem(at: url) }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            var value = try JSONDecoder().decode(CharacterLibraryArchive.self, from: Data(contentsOf: url))
            guard [1, 2].contains(value.schemaVersion) else { throw CocoaError(.coderReadCorrupt) }
            let legacy = value.schemaVersion == 1
            for id in Set(Array(value.accounts.keys) + value.creations.map(\.ownerID)).sorted() {
                Self.ensureAuthor(for: id, in: &value)
            }
            for index in value.creations.indices {
                value.creations[index].authorID = value.authorByAccount[value.creations[index].ownerID]
            }
            for id in Array(value.accounts.keys) {
                guard var account = value.accounts[id] else { continue }
                account.subscriptions = Self.unique(account.subscriptions)
                account.followedAuthors = Self.unique(account.followedAuthors).filter { $0 != value.authorByAccount[id] }
                value.accounts[id] = account
            }
            value.schemaVersion = 2
            archive = value
            if legacy {
                let backup = url.appendingPathExtension("v1.backup")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
                try Self.write(value, to: url)
            }
        } catch { blocked = true; self.error = "角色目录读取或升级失败，已保留原文件，暂时停止修改。" }
    }
    var subscriptions: [String] { (archive.accounts[accountID]?.subscriptions ?? []).filter { model($0) != nil } }
    var followedAuthors: [String] { archive.accounts[accountID]?.followedAuthors ?? [] }
    /// List visibility is separate from subscriptions and the conversation archive.
    /// A newer message restores visibility; old history remains locally searchable.
    func isConversationHidden(_ id:String, latestMessage:Date? = nil) -> Bool {
        guard let hiddenAt = archive.accounts[accountID]?.hiddenConversations[id] else { return false }
        return (latestMessage ?? .distantPast) <= hiddenAt
    }
    @discardableResult func hideConversation(_ id:String, latestMessage:Date? = nil) -> Bool {
        guard model(id) != nil, archive.accounts[accountID] != nil else { return false }
        let hiddenAt = max(Date(),latestMessage ?? .distantPast)
        return commit { $0.accounts[accountID]?.hiddenConversations[id] = hiddenAt }
    }
    @discardableResult func restoreConversation(_ id:String) -> Bool {
        guard archive.accounts[accountID]?.hiddenConversations[id] != nil else { return true }
        return commit { $0.accounts[accountID]?.hiddenConversations.removeValue(forKey:id) }
    }
    var availableSubscriptions: [ModelDescriptor] { subscriptions.compactMap(model) }
    var currentAuthor: AuthorProfile? { archive.authorByAccount[accountID].flatMap { author($0) } }
    var lastCharacter: String? {
        let last = archive.accounts[accountID]?.lastCharacter
        return last.flatMap { subscriptions.contains($0) && model($0) != nil ? $0 : nil }
            ?? subscriptions.first(where: { model($0) != nil })
    }
    var creations: [OwnedCharacter] { archive.creations.filter { item in item.ownerID == accountID && ModelDescriptor.all.contains { $0.id == item.baseID } } }
    var discover: [ModelDescriptor] {
        ModelDescriptor.all + archive.creations.filter { $0.published || $0.ownerID == accountID }.compactMap { model($0.id) }
    }
    var discoverAuthors: [AuthorProfile] {
        let publicIDs = Set(archive.creations.filter(\.published).compactMap(\.authorID))
        let ids = publicIDs.union(followedAuthors).union(currentAuthor.map { [$0.id] } ?? [])
        return [AuthorProfile.starry] + ids.filter { $0 != AuthorProfile.starry.id }.compactMap { author($0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var followedAuthorWorks: [ModelDescriptor] {
        let followed = Set(followedAuthors)
        return discover.filter { author(for: $0.id).map { followed.contains($0.id) } ?? false }
            .sorted { updatedAt($0.id) == updatedAt($1.id) ? $0.id < $1.id : updatedAt($0.id) > updatedAt($1.id) }
    }
    func model(_ id: String) -> ModelDescriptor? {
        if let base = ModelDescriptor.all.first(where: { $0.id == id }) { return base }
        guard let item = archive.creations.first(where: { $0.id == id && ($0.published || $0.ownerID == accountID) }),
              let base = ModelDescriptor.all.first(where: { $0.id == item.baseID }) else { return nil }
        if let collection = item.collection, !collection.isCompatible(with: base) { return nil }
        return base.instance(id: item.id, collection: item.collection, authoredProfile: item.profile)
    }
    func author(_ id: String) -> AuthorProfile? { id == AuthorProfile.starry.id ? .starry : archive.authors[id] }
    func author(for characterID: String) -> AuthorProfile? {
        guard model(characterID) != nil else { return nil }
        if ModelDescriptor.all.contains(where: { $0.id == characterID }) { return .starry }
        return archive.creations.first { $0.id == characterID }?.authorID.flatMap { author($0) }
    }
    func publicWorks(by authorID: String) -> [ModelDescriptor] {
        if authorID == AuthorProfile.starry.id { return ModelDescriptor.all }
        return archive.creations.filter { $0.authorID == authorID && $0.published }
            .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }.compactMap { model($0.id) }
    }
    func followers(of authorID: String) -> [AuthorProfile] {
        // Local counts reflect signed-in demo identities only, not invented
        // network popularity. Guests have no public author profile.
        archive.accounts.filter { $0.key != "guest" && $0.value.followedAuthors.contains(authorID) }
            .compactMap { archive.authorByAccount[$0.key].flatMap { author($0) } }.sorted { $0.id < $1.id }
    }
    func updatedAt(_ id: String) -> Date { archive.creations.first { $0.id == id }.map { $0.updatedAt ?? $0.createdAt } ?? .distantPast }
    func publishedProfile(_ id: String) -> CharacterProfile? { creation(id)?.profile }
    func creation(_ id: String) -> OwnedCharacter? { archive.creations.first { $0.id == id && ($0.published || $0.ownerID == accountID) } }
    func hasAccount(_ id: String) -> Bool { archive.accounts[id] != nil }
    func activate(_ id: String, existing: [String: CharacterRecord], adoptingGuest: Bool = false) {
        accountID = id
        if let old = archive.accounts[id], !old.subscriptions.isEmpty,
           old.subscriptions.allSatisfy({ model($0) == nil }) {
            commit { state in
                var account = old
                account.subscriptions = [ModelDescriptor.defaultCharacter.id]
                account.lastCharacter = ModelDescriptor.defaultCharacter.id
                state.accounts[id] = account
            }
        }
        if archive.accounts[id] != nil && (id == "guest" || currentAuthor != nil) { return }
        commit { state in
            Self.ensureAuthor(for: id, in: &state)
            guard state.accounts[id] == nil else { return }
            if id != "guest", adoptingGuest, state.guestImportedBy == nil, let guest = state.accounts["guest"] {
                state.accounts[id] = guest; state.guestImportedBy = id
            } else {
                let history = ModelDescriptor.all.filter { !(existing[$0.id]?.messages.isEmpty ?? true) }
                    .sorted { (existing[$0.id]?.messages.last?.date ?? .distantPast) > (existing[$1.id]?.messages.last?.date ?? .distantPast) }
                let ids = history.isEmpty ? [ModelDescriptor.defaultCharacter.id] : history.map(\.id)
                state.accounts[id] = CharacterLibraryAccount(subscriptions: ids, lastCharacter: ids.first)
            }
        }
    }
    @discardableResult func subscribe(_ id: String, _ value: Bool) -> Bool {
        guard !blocked else { return false }
        guard !value || model(id) != nil else { error = "这个角色暂时不可用。"; return false }
        guard subscriptions.contains(id) != value else { error = nil; return true }
        return commit { state in
            var account = state.accounts[accountID] ?? CharacterLibraryAccount(subscriptions: [])
            if value { account.subscriptions.append(id) } else { account.subscriptions.removeAll { $0 == id } }
            if !value && account.lastCharacter == id { account.lastCharacter = account.subscriptions.first { model($0) != nil } }
            state.accounts[accountID] = account
        }
    }
    @discardableResult func followAuthor(_ id: String, _ value: Bool) -> Bool {
        guard !blocked else { return false }
        guard !value || (author(id) != nil && id != currentAuthor?.id) else { error = "不能关注自己或暂不可用的作者。"; return false }
        guard followedAuthors.contains(id) != value else { error = nil; return true }
        return commit { state in
            var account = state.accounts[accountID] ?? CharacterLibraryAccount(subscriptions: [])
            if value { account.followedAuthors.append(id) } else { account.followedAuthors.removeAll { $0 == id } }
            state.accounts[accountID] = account
        }
    }
    @discardableResult func updateAuthor(_ profile: AuthorProfile) -> Bool {
        guard !blocked, accountID != "guest", currentAuthor?.id == profile.id else { error = "只能编辑自己的作者资料。"; return false }
        var clean = profile
        clean.name = String(clean.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        clean.bio = String(clean.bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !clean.name.isEmpty else { error = "请给作者起一个名字。"; return false }
        guard AuthorProfile.avatarChoices.contains(clean.avatar) else { error = "请选择可用的头像。"; return false }
        clean.revision = currentAuthor!.revision
        if clean == currentAuthor { error = nil; return true }
        clean.revision += 1
        return commit { $0.authors[clean.id] = clean }
    }
    @discardableResult func select(_ id: String, showInMessages:Bool = true) -> Bool {
        guard !blocked, model(id) != nil else { return false }
        if archive.accounts[accountID]?.lastCharacter == id, subscriptions.contains(id),
           !showInMessages || archive.accounts[accountID]?.hiddenConversations[id] == nil { return true }
        return commit { state in
            var account = state.accounts[accountID] ?? CharacterLibraryAccount(subscriptions: [])
            if !account.subscriptions.contains(id) { account.subscriptions.append(id) }
            if showInMessages { account.hiddenConversations.removeValue(forKey:id) }
            account.lastCharacter = id; state.accounts[accountID] = account
        }
    }
    @discardableResult func create(base: ModelDescriptor, profile: CharacterProfile, published: Bool) -> String? {
        guard accountID != "guest" else { error = "登录后可以创建角色。"; return nil }
        let id = "character-" + UUID().uuidString.lowercased()
        let collection = base.collection.scoped(to:id)
        guard commit({ state in
            Self.ensureAuthor(for: accountID, in: &state)
            state.creations.append(OwnedCharacter(id: id, ownerID: accountID, baseID: base.runtimeID,
                profile: collection.normalize(profile), published: published, createdAt: Date(), collection: collection,
                authorID: state.authorByAccount[accountID], updatedAt: Date(), revision: 1))
            var account = state.accounts[accountID] ?? CharacterLibraryAccount(subscriptions: [])
            account.subscriptions.append(id); account.lastCharacter = id; state.accounts[accountID] = account
        }) else { return nil }
        return id
    }
    @discardableResult func publish(_ id: String, value: Bool, profile: CharacterProfile) -> Bool {
        guard !blocked, let index = archive.creations.firstIndex(where: { $0.id == id && $0.ownerID == accountID }), model(id) != nil else {
            if !blocked { error = "只能发布或更新自己的角色。" }; return false
        }
        if archive.creations[index].published == value { error = nil; return true }
        return commit {
            $0.creations[index].published = value
            $0.creations[index].updatedAt = Date(); $0.creations[index].revision = ($0.creations[index].revision ?? 0) + 1
        }
    }
    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>(); return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private static func ensureAuthor(for account: String, in state: inout CharacterLibraryArchive) {
        guard account != "guest" else { return }
        if let id = state.authorByAccount[account], id != AuthorProfile.starry.id, state.authors[id] != nil { return }
        let id = "author-" + UUID().uuidString.lowercased()
        state.authorByAccount[account] = id; state.authors[id] = .initial(id: id, accountID: account)
    }
    private static func write(_ archive: CharacterLibraryArchive, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    @discardableResult private func commit(_ change: (inout CharacterLibraryArchive) -> Void) -> Bool {
        guard !blocked else { return false }
        var next = archive; change(&next)
        do { try Self.write(next, to: url); archive = next; error = nil; return true }
        catch { self.error = "资料保存失败，请检查剩余空间后重试。"; return false }
    }
}
