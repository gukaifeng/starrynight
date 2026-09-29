import Foundation

enum CustomizationDestination: String, CaseIterable, Identifiable {
    case memory, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .memory: "共同记忆"
        case .history: "聊天资料"
        }
    }
    var detail: String {
        switch self {
        case .memory: "留住我们之间重要的小事"
        case .history: "回看、搜索与分享对话"
        }
    }
    var symbol: String {
        switch self {
        case .memory: "bookmark"
        case .history: "clock.arrow.circlepath"
        }
    }
}
