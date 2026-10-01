import Foundation

extension Notification.Name { static let accountDataChanged = Notification.Name("starry.account-data.changed") }

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
    var atmosphereEnabled:Bool? = nil // Legacy on/off is read until a level is chosen.
    var atmosphereLevel:Int? = nil
    var resolvedAtmosphereLevel:Int {min(4,max(0,atmosphereLevel ?? (atmosphereEnabled == false ? 0 : 2)))}
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
    var aiScript: AIScript? = nil
    var source: String? = nil
    // A late narration enriches the same message. Track visible content rather
    // than only message count, and exclude audio duration/playback metadata.
    var visibleContentKey: [String] {
        var parts = [id.uuidString,role,text]
        for beat in aiScript?.beats ?? [] {
            parts.append(contentsOf:[beat.beatId,beat.dialogue?.text ?? "",beat.visibleThought ?? ""])
            parts.append(contentsOf:beat.narrations.map(\.text))
            parts.append(contentsOf:beat.parts?.map { $0.kind+"|"+$0.text } ?? [])
        }
        return parts
    }
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
    var conversationResetID:String? = nil
    var conversationResetVersion:Int? = nil
    var pendingDeletionID:String? = nil
    var lastViewPose: CharacterViewPose { (viewPose ?? viewLibrary?.selected ?? .original).normalized }
    mutating func resetConversation(_ id:String,version:Int=0) {
        messages=[];memories=[];greeting=nil
        experiences=CompanionExperiences(preferences:together.preferences)
        conversationResetID=id;conversationResetVersion=version;pendingDeletionID=nil
    }
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
    var schemaVersion = 2
    var characters: [String:CharacterRecord] = [:]
    // Decode legacy archives, but never use their old account-level display preference.
    var chatDisplay: ChatDisplaySettings? = nil
    var guestTurns: Int? = nil
    var guestImportedBy: String? = nil
    // Optional for schema-2 archives created before account-wide addressing.
    var defaultNicknames: [String:String]? = nil
}
enum CompanionPersistence {
    private static let queue=DispatchQueue(label:"app.starry.journal",qos:.utility)
    static func read(_ url: URL) throws -> CompanionArchive {
        try queue.sync {try readFile(url)}
    }
    private static func readFile(_ url:URL) throws -> CompanionArchive {
        guard FileManager.default.fileExists(atPath:url.path) else { return CompanionArchive() }
        let archive = try JSONDecoder().decode(CompanionArchive.self,from:Data(contentsOf:url))
        guard (1...2).contains(archive.schemaVersion) else { throw CocoaError(.fileReadCorruptFile) }
        return archive
    }
    static func write(_ archive: CompanionArchive, to url: URL) throws {
        try queue.sync {try writeFile(archive,to:url)}
    }
    static func enqueue(_ archive:CompanionArchive,to url:URL,completion:@escaping @Sendable (Result<Void,Error>)->Void) {
        queue.async {completion(Result {try writeFile(archive,to:url)})}
    }
    static func flush() async {await withCheckedContinuation {continuation in queue.async {continuation.resume()}}}
    private static func writeFile(_ archive:CompanionArchive,to url:URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(archive).write(to:url,options:.atomic)
#if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:url.path)
#endif
    }
}
