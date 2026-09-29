import Foundation

struct CharacterProfile: Codable, Equatable, Sendable {
    var name: String
    var background = "一起分享日常、慢慢了解彼此的伙伴。"
    var personality = "温柔"
    var tone = "自然"
    var concise = false
    var accent = "玉青"
    var ambience = "晨光"
    var autoSpeak = true
    var voiceSpeed = 1.0
    // Optional for synthesized Codable compatibility with existing v0.3 archives.
    var voiceID: String? = nil
    var audio: CharacterAudioPreferences? = nil
    var framing: CharacterFraming? = nil
    var studio: CharacterStudio? = nil
    var resolvedStudio: CharacterStudio { (studio ?? .recommended).normalized }
    var resolvedFraming: CharacterFraming { (framing ?? .recommended).normalized }
    static func initial(_ id: String) -> Self {
        guard let model = ModelDescriptor.all.first(where:{ $0.id == id }) else { return Self(name:"伙伴") }
        var profile = Self(name:model.name)
        // Packages supply the starting story; saved user settings remain intact.
        profile.background = model.display.description
        return profile
    }
    mutating func normalize() {
        name = String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(24))
        if name.isEmpty { name = "伙伴" }
        background = String(background.prefix(500))
        voiceSpeed = voiceSpeed.isFinite ? min(1.4,max(0.7,voiceSpeed)) : 1
        if framing != nil { framing = resolvedFraming }
        if studio != nil { studio = resolvedStudio }
    }
}
struct CompanionMessage: Codable, Identifiable, Sendable {
    var id = UUID()
    var role: String
    var text: String
    var date = Date()
    var liked = false
    var interrupted = false
    // Optional metadata; old conversations decode unchanged. The speed disambiguates
    // measured durations after the user changes the character's voice preferences.
    var speechDuration: Double? = nil
    var speechSpeed: Double? = nil
    // Open string metadata allows future entry scenes without breaking old archives.
    var proactiveScene: String? = nil
    var storyID: String? = nil
}
struct CompanionMemory: Codable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var date = Date()
}
struct CharacterRecord: Codable, Sendable {
    var profile: CharacterProfile
    var messages: [CompanionMessage] = []
    var memories: [CompanionMemory] = []
    var greeting: ConversationGreetingHistory? = nil
    var experiences: CompanionExperiences? = nil
    var viewLibrary: CharacterViewLibrary? = nil // Decode v0.43, clear after migration.
    var viewPose: CharacterViewPose? = nil
    var lastViewPose: CharacterViewPose { (viewPose ?? viewLibrary?.selected ?? .original).normalized }
}
struct ConversationGreetingHistory: Codable, Sendable {
    var count: Int
    var lastDate: Date
    var lastText: String
    var lastEntryID: UUID
}
struct ChatDisplaySettings: Codable, Equatable, Sendable {
    // Retained for decoding older journals; presentation height is now fixed.
    var heightFraction = 0.60
    var fontSize = 15.0
    var normalized: Self {
        Self(heightFraction:0.60,fontSize:fontSize.isFinite ? min(24,max(14,fontSize)) : 15)
    }
    // A new device-wide preference deliberately ignores the old journal value.
    static let fontPreferenceKey = "starry.chat.font-size.v2"
    static func fixturePreferenceSuite(for url:URL) -> String {
        // Keep fixture domains deterministic and short even inside long simulator paths.
        let hash = url.standardizedFileURL.path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return "starry.chat-display.fixture."+String(hash,radix:16)
    }
    static func load(from defaults:UserDefaults) -> Self {
        guard let value = defaults.object(forKey:fontPreferenceKey) as? NSNumber else { return Self() }
        return Self(fontSize:value.doubleValue).normalized
    }
    func save(to defaults:UserDefaults) {
        defaults.set(normalized.fontSize,forKey:Self.fontPreferenceKey)
    }
}
struct CompanionArchive: Codable, Sendable {
    var schemaVersion = 1
    var characters: [String:CharacterRecord] = [:]
    // Decode legacy archives, but never use their old account-level display preference.
    var chatDisplay: ChatDisplaySettings? = nil
    var guestTurns: Int? = nil
    var guestImportedBy: String? = nil
}
struct DialogueRule: Codable, Sendable {
    var id: String
    var keywords: [String]
    var replies: [String]
    var eventName: String?
    var emotion: String?
}
struct DialogueReply: Sendable { var text: String; var eventName: String; var emotion: String }
protocol DialogueProviding: Sendable {
    func reply(to input: String, record: CharacterRecord, variant: Int) -> DialogueReply
    func greeting(for context:ConversationGreetingContext,record:CharacterRecord) -> DialogueReply
}
struct LocalDialogue: DialogueProviding {
    let rules: [DialogueRule]
    init(data: Data) throws { rules = try JSONDecoder().decode([DialogueRule].self,from:data) }
    func reply(to input: String, record: CharacterRecord, variant: Int = 0) -> DialogueReply {
        if var special = LocalTogetherDialogue.override(input,record:record) {
            let nickname = record.together.preferences.normalized.nickname
            if !nickname.isEmpty { special.text = nickname + "，" + special.text }
            return special
        }
        let query = input.lowercased()
        let p = record.profile
        let rule = rules.first { $0.keywords.contains { query.contains($0.lowercased()) } } ?? rules.last!
        let memories = record.memories.suffix(6).map(\.text).joined(separator:"；")
        var text = rule.replies[abs(variant) % rule.replies.count]
            .replacingOccurrences(of:"{name}",with:p.name)
            .replacingOccurrences(of:"{background}",with:p.background)
            .replacingOccurrences(of:"{memory}",with:memories.isEmpty ? "你还没有保存记忆。可以把喜欢的事写进记忆里，我下次就能提起。" : "你保存的记忆是：" + memories + "。这些内容随时可以修改或删除。")
        if rule.id == "continue", let previous = record.messages.last(where: { $0.role == "user" && $0.text != input }) {
            text = "刚才你说“\(previous.text.prefix(70))”。我们可以从这件事里最在意的部分继续。"
        }
        if !["memory","identity"].contains(rule.id) {
            if p.personality == "活泼" { text = "嘿，" + text }
            if p.personality == "理性" { text = "我们慢慢理清楚。" + text }
            if p.tone == "温暖" { text += " 我会认真听。" }
            if p.tone == "轻松" { text += " 不着急，给今天留一点松弛感。" }
        }
        let nickname = record.together.preferences.normalized.nickname
        if !nickname.isEmpty { text = nickname + "，" + text }
        if p.concise && rule.id != "memory" { text = String(text.prefix(85)) }
        return DialogueReply(text:text,eventName:rule.eventName ?? "dialogue.reply",emotion:rule.emotion ?? "neutral")
    }
}

enum CompanionPersistence {
    static func read(_ url: URL) throws -> CompanionArchive {
        guard FileManager.default.fileExists(atPath:url.path) else { return CompanionArchive() }
        let archive = try JSONDecoder().decode(CompanionArchive.self,from:Data(contentsOf:url))
        guard archive.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return archive
    }
    static func write(_ archive: CompanionArchive, to url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(archive).write(to:url,options:.atomic)
#if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:url.path)
#endif
    }
}
