import Foundation

struct TogetherPreferences: Codable, Equatable, Sendable {
    var nickname = ""
    var aboutMe = ""
    var relationship = "朋友"
    var responseStyle = "先听我说"
    var avoidedTopics = ""
    var normalized: Self {
        var value = self
        value.nickname = String(nickname.trimmingCharacters(in:.whitespacesAndNewlines).prefix(20))
        value.aboutMe = String(aboutMe.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
        value.avoidedTopics = String(avoidedTopics.trimmingCharacters(in:.whitespacesAndNewlines).prefix(200))
        if !["朋友","搭档","知己"].contains(relationship) { value.relationship = "朋友" }
        if !["先听我说","一起想办法","轻松聊聊"].contains(responseStyle) { value.responseStyle = "先听我说" }
        return value
    }
    func avoids(_ input:String) -> Bool {
        avoidedTopics.components(separatedBy:CharacterSet(charactersIn:",，、;；\n"))
            .map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
            .contains { $0.count >= 2 && input.localizedCaseInsensitiveContains($0) }
    }
}

struct MemorySuggestion: Codable, Identifiable, Sendable {
    var id = UUID()
    let sourceMessageID: UUID
    let text: String
    var date = Date()
}
struct TogetherMoment: Codable, Identifiable, Sendable {
    var id = UUID()
    var kind: String
    var title: String
    var text: String
    var date = Date()
}
struct StoryProgress: Codable, Equatable, Sendable {
    let storyID: String
    var revision = 1
    var nodeID = "start"
    var choices: [String] = []
    var completed = false
    var updatedAt = Date()
}
struct CompanionExperiences: Codable, Sendable {
    var preferences = TogetherPreferences()
    var stories: [String:StoryProgress] = [:]
    var activeStoryID: String? = nil
    var moments: [TogetherMoment] = []
    var suggestions: [MemorySuggestion] = []
    // Stable source IDs prevent ignored candidates from reappearing on replay.
    var reviewedMemorySources: [UUID] = []
}
extension CharacterRecord {
    var together: CompanionExperiences { experiences ?? CompanionExperiences() }
}

/// Story cards are prompts, never prewritten assistant replies or branch tables.
struct CompanionStory: Identifiable, Sendable {
    let id, title, subtitle, category, symbol: String
    static let all: [Self] = [
        .init(id:"rain-letter",title:"雨夜来信",subtitle:"一封没有署名的信，等我们一起发现来处。",category:"日常",symbol:"envelope.open"),
        .init(id:"after-class",title:"放学后的天台",subtitle:"风翻开画册，一起想象晚霞里的小小冒险。",category:"校园",symbol:"sun.horizon"),
        .init(id:"star-signal",title:"星海来客",subtitle:"一段遥远的信号，两个人共同书写的旅程。",category:"幻想",symbol:"sparkle")
    ]
    static func available(for model:ModelDescriptor) -> [Self] { all }
}

enum MemoryCandidates {
    static func extract(_ message:CompanionMessage,record:CharacterRecord) -> MemorySuggestion? {
        guard message.role == "user", message.storyID == nil else { return nil }
        let text = message.text.trimmingCharacters(in:.whitespacesAndNewlines)
        let markers = ["我喜欢","我最喜欢","我的爱好是","我的目标是","我希望你叫我","请记住：","记住："]
        guard (4...150).contains(text.count), markers.contains(where:{ text.hasPrefix($0) }),
              !text.contains("？"), !text.contains("?"), !record.together.preferences.avoids(text),
              !record.memories.contains(where:{ $0.text == text }),
              !record.together.suggestions.contains(where:{ $0.text == text || $0.sourceMessageID == message.id }),
              !record.together.reviewedMemorySources.contains(message.id) else { return nil }
        return MemorySuggestion(sourceMessageID:message.id,text:text,date:message.date)
    }
}

/// Versioned value passed to a future provider. Unconfirmed suggestions never enter it.
struct CompanionContextV1: Codable, Sendable {
    let version: Int
    let characterID, characterName, characterBackground, characterPersonality, characterTone: String
    let preferences: TogetherPreferences
    let confirmedMemories: [String]
    let activeStory: StoryProgress?
    init(characterID:String,record:CharacterRecord) {
        version = 1; self.characterID = characterID; characterName = record.profile.name
        characterBackground = record.profile.background; preferences = record.together.preferences.normalized
        characterPersonality = record.profile.personality; characterTone = record.profile.tone
        confirmedMemories = record.memories.suffix(30).map(\.text)
        activeStory = record.together.activeStoryID.flatMap { record.together.stories[$0] }
    }
}
