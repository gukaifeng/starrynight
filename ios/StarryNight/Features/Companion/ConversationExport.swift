import Foundation
import UIKit

/// A deliberately small, immutable sharing boundary. Account details, memories,
/// relationship settings, voice files and unselected conversations never enter it.
struct ConversationExportSnapshot: Identifiable, Sendable {
    let id = UUID()
    struct Message: Identifiable, Sendable {
        let id: UUID
        let role: String
        let text: String
        let date: Date
    }
    let characterID: String
    let characterName: String
    let portraitPNG: Data?
    let messages: [Message]

    init(characterID: String, characterName: String, portraitPNG: Data?, messages: [CompanionMessage]) {
        self.characterID = characterID; self.characterName = characterName
        self.portraitPNG = portraitPNG
        self.messages = messages.filter {
            ["user", "assistant"].contains($0.role) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map { Message(id: $0.id, role: $0.role, text: $0.text, date: $0.date) }
    }

    @MainActor static func capture(model: ModelDescriptor, record: CharacterRecord,
                                    portraits: CharacterPortraitStore?) -> Self {
        let portrait = portraits?.image(model, profile: record.profile)
            ?? UIImage(named: model.thumbnail + "Portrait") ?? UIImage(named: model.thumbnail)
        return Self(characterID: model.id, characterName: record.profile.name,
                    portraitPNG: portrait?.pngData(), messages: record.messages)
    }
}

/// Endpoints refer to the frozen snapshot, not the live/streaming chat window.
struct ConversationExportRange: Equatable, Sendable {
    private(set) var lower: Int
    private(set) var upper: Int
    let total: Int
    init(total: Int, recent: Int = 10) {
        self.total = max(0, total)
        lower = max(0, total - max(1, recent)); upper = max(-1, total - 1)
    }
    var count: Int { total == 0 ? 0 : upper - lower + 1 }
    mutating func setStart(_ index: Int) {
        guard total > 0 else { return }
        lower = min(total - 1, max(0, index)); upper = max(upper, lower)
    }
    mutating func setEnd(_ index: Int) {
        guard total > 0 else { return }
        upper = min(total - 1, max(0, index)); lower = min(lower, upper)
    }
    func selected(from snapshot: ConversationExportSnapshot) throws -> [ConversationExportSnapshot.Message] {
        guard total == snapshot.messages.count, count > 0, lower >= 0, upper < total else {
            throw ConversationExportError.emptyRange
        }
        return Array(snapshot.messages[lower...upper])
    }
}

enum ConversationImageStyle: String, CaseIterable, Identifiable, Sendable {
    case moon, paper
    var id: String { rawValue }
    var name: String { self == .moon ? "月夜" : "暖笺" }
    var detail: String { self == .moon ? "深墨与柔光" : "奶油色信纸" }
}
struct ConversationExportOptions: Sendable {
    var style: ConversationImageStyle = .moon
    var showsDates = false
}
enum ConversationExportError: LocalizedError {
    case emptyRange, tooLarge, cannotRender
    var errorDescription: String? {
        switch self {
        case .emptyRange: "请先选择一段有文字的对话。"
        case .tooLarge: "这段对话太长了，请缩小范围，分次导出。"
        case .cannotRender: "长图暂时未能生成，请重试。"
        }
    }
}
struct ConversationImagePage: Identifiable, Sendable {
    var id: URL { imageURL }
    let imageURL: URL
    let previewURL: URL
    let width: Int
    let height: Int
}
struct ConversationImageResult: Sendable {
    let directory: URL
    let pages: [ConversationImagePage]
    let messageCount: Int
    var cacheLease: CacheFileLease? = nil
}
