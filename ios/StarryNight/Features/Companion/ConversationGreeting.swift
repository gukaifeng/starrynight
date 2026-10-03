import Foundation

enum ConversationEntryReason: Sendable {
    case appLaunch, characterSelection, conversationReturn, foregroundReturn
}

struct ConversationEntry: Sendable {
    var id = UUID()
    let reason: ConversationEntryReason
    let characterID: String
    let accountID: String
}

/// Entry IDs deduplicate renderer callbacks. A fresh launch or a different role
/// gets a contextual welcome; retained-tab and foreground returns stay quiet.
enum ConversationGreetingPolicy {
    static func shouldIntroduce(_ record:CharacterRecord) -> Bool {
        record.greeting == nil && record.messages.isEmpty
    }
    static func shouldGreet(_ record:CharacterRecord,entry:ConversationEntry) -> Bool {
        guard record.greeting?.lastEntryID != entry.id else { return false }
        return shouldIntroduce(record) || entry.reason == .appLaunch || entry.reason == .characterSelection
    }
}

/// Only confirmed on-screen entries reach this policy; mounting a view or opening
/// a profile sheet is not a new conversation. History is scoped by the store.
struct ConversationGreetingContext: Sendable {
    let scene: String
    let date: Date
    let hour: Int
    let returningAfterDays: Bool
    let hasUserMessages: Bool

    static func make(reason:ConversationEntryReason,record:CharacterRecord,hasMetAnyone:Bool,
                     now:Date = Date(),calendar:Calendar = .current) -> Self {
        let known = record.greeting != nil || !record.messages.isEmpty
        let scene: String
        if !known {
            scene = reason == .appLaunch && !hasMetAnyone ? "firstLaunch" : "firstMeeting"
        } else {
            switch reason {
            case .appLaunch: scene = "appLaunch"
            case .characterSelection: scene = "characterSwitch"
            case .conversationReturn: scene = "conversationReturn"
            case .foregroundReturn: scene = "foregroundReturn"
            }
        }
        // Last real activity wins over an older welcome; never invent an absence
        // when the archive has just been migrated or the clock moved backwards.
        let last = [record.greeting?.lastDate,record.messages.last?.date].compactMap { $0 }.max()
        return Self(scene:scene,date:now,hour:calendar.component(.hour,from:now),
                    returningAfterDays:last.map { now.timeIntervalSince($0) >= 3*24*3600 } ?? false,
                    hasUserMessages:record.messages.contains { $0.role == "user" })
    }
}
