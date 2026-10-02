import Foundation

/// Public creator identity. Login IDs, contact details and private preferences
/// belong to AccountStore/CompanionStore and are never copied into this record.
struct AuthorProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var bio: String
    var avatar: String
    var revision = 1
    var isBuiltin: Bool { id == Self.starry.id }
    var handle: String { isBuiltin ? "@starry" : "@" + String(id.replacingOccurrences(of: "author-", with: "").prefix(8)) }
    static let starry = Self(id: "starry-studio", name: "星夜", bio: "认真打磨每一次相遇。这里收录星夜整理的内置角色与相处设定，3D 素材原作者另行署名。", avatar: "starry")
    static let avatarChoices = ["moon", "leaf", "sparkle", "sun", "cloud", "wave"]
    static func initial(id: String, accountID: String) -> Self {
        Self(id: id, name: accountID == DemoAccount.id ? "星夜体验者 A" : accountID == DemoAccount.alternateID ? "星夜体验者 B" : "星夜创作者",
             bio: "在星夜，遇见温柔。", avatar: "moon")
    }
    func matches(_ query: String) -> Bool {
        let text = (name + " " + bio + " " + handle).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return query.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).allSatisfy { text.contains($0) }
    }
}

struct OwnedCharacter: Codable, Identifiable {
    let id: String
    let ownerID: String
    let baseID: String
    var profile: CharacterProfile
    var published: Bool
    let createdAt: Date
    var collection: CharacterCollection? = nil
    var authorID: String? = nil // Backfilled before a v1 archive is committed as v2.
    var updatedAt: Date? = nil
    var revision: Int? = nil
}
struct CharacterLibraryAccount: Codable {
    var subscriptions: [String]
    var followedAuthors: [String] = []
    var lastCharacter: String?
    var hiddenConversations: [String:Date] = [:]
    private enum CodingKeys: String, CodingKey { case subscriptions, followedAuthors, lastCharacter, followed, hiddenConversations }
    init(subscriptions: [String], followedAuthors: [String] = [], lastCharacter: String? = nil) {
        self.subscriptions = subscriptions; self.followedAuthors = followedAuthors; self.lastCharacter = lastCharacter
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An explicitly empty new list wins over the legacy field. Author
        // follows are never inferred from former character follows.
        subscriptions = try c.decodeIfPresent([String].self, forKey: .subscriptions)
            ?? c.decodeIfPresent([String].self, forKey: .followed) ?? []
        followedAuthors = try c.decodeIfPresent([String].self, forKey: .followedAuthors) ?? []
        lastCharacter = try c.decodeIfPresent(String.self, forKey: .lastCharacter)
        hiddenConversations = try c.decodeIfPresent([String:Date].self, forKey: .hiddenConversations) ?? [:]
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(subscriptions, forKey: .subscriptions); try c.encode(followedAuthors, forKey: .followedAuthors)
        try c.encodeIfPresent(lastCharacter, forKey: .lastCharacter)
        try c.encode(hiddenConversations, forKey: .hiddenConversations)
    }
}
struct CharacterLibraryArchive: Codable {
    var schemaVersion = 2
    var accounts: [String: CharacterLibraryAccount] = [:]
    var creations: [OwnedCharacter] = []
    var authors: [String: AuthorProfile] = [:]
    /// Private local join table. Public author IDs never encode a login ID.
    var authorByAccount: [String: String] = [:]
    var guestImportedBy: String?
    private enum CodingKeys: String, CodingKey { case schemaVersion, accounts, creations, authors, authorByAccount, guestImportedBy }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        accounts = try c.decode([String: CharacterLibraryAccount].self, forKey: .accounts)
        creations = try c.decode([OwnedCharacter].self, forKey: .creations)
        authors = try c.decodeIfPresent([String: AuthorProfile].self, forKey: .authors) ?? [:]
        authorByAccount = try c.decodeIfPresent([String: String].self, forKey: .authorByAccount) ?? [:]
        guestImportedBy = try c.decodeIfPresent(String.self, forKey: .guestImportedBy)
    }
}
