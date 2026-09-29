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

extension DialogueProviding {
    func greeting(for context:ConversationGreetingContext,record:CharacterRecord) -> DialogueReply {
        LocalConversationGreeting.reply(context:context,record:record)
    }
}

enum LocalConversationGreeting {
    static func reply(context:ConversationGreetingContext,record:CharacterRecord) -> DialogueReply {
        let profile = record.profile
        let timeGreeting: String
        switch context.hour {
        case 5..<11: timeGreeting = "早上好"
        case 11..<14: timeGreeting = "中午好"
        case 14..<18: timeGreeting = "下午好"
        default: timeGreeting = "晚上好"
        }
        let options: [String]
        switch context.scene {
        case "firstLaunch":
            options = ["你好，我是\(profile.name)。欢迎来到星夜，很高兴认识你。今天想聊些什么？"]
        case "firstMeeting":
            options = ["你好，我是\(profile.name)。这是我们第一次见面，你希望我怎么称呼你？"]
        case "appLaunch":
            options = context.returningAfterDays
                ? ["\(timeGreeting)，有几天没见啦。最近过得怎么样？", "\(timeGreeting)，很高兴又见到你。这几天有什么想和我分享的吗？"]
                : ["\(timeGreeting)，又见面了。今天过得怎么样？", "\(timeGreeting)，你来啦。今天有什么想说的？", "\(timeGreeting)，很高兴又见到你。想聊点什么？"]
        case "characterSwitch":
            options = context.hasUserMessages
                ? ["又来找我啦。上次的话题想接着聊，还是说点新鲜事？", "很高兴再见到你。我们继续聊聊吧。"]
                : ["又见面啦。这次想聊些什么？", "你来啦，有什么想和我分享的吗？"]
        case "foregroundReturn":
            options = context.hasUserMessages
                ? ["回来啦。刚才的话，还想接着说吗？", "欢迎回来，我在。我们接着慢慢聊。"]
                : ["回来啦。想好从什么聊起了吗？", "欢迎回来。今天过得怎么样？"]
        default:
            if context.returningAfterDays {
                options = ["好几天没聊了，很高兴见到你。最近怎么样？", "又见到你了。这几天有什么新鲜事吗？"]
            } else if context.hasUserMessages {
                options = ["回来啦，我们接着聊。", "我在，刚才的话可以接着慢慢说。", "又见到你啦。想继续刚才的话题吗？"]
            } else {
                options = ["你回来啦。这次想聊些什么？", "又见到你了。今天有什么想和我分享的吗？", "我在，想说什么就慢慢说。"]
            }
        }
        func styled(_ text:String) -> String {
            var value = text
            let nickname = record.together.preferences.normalized.nickname
            if profile.personality == "活泼" { value = "嘿，" + value }
            else if profile.personality == "理性" && context.scene == "firstMeeting" {
                value = "你好，我是\(profile.name)。很高兴认识你，有什么想一起聊聊的问题吗？"
            }
            if profile.tone == "温暖" { value += " 我会认真听。" }
            if !nickname.isEmpty {
                value = nickname + "，" + value.replacingOccurrences(of:"你希望我怎么称呼你？",with:"今天想从什么聊起？")
            }
            if profile.concise { value = String(value.prefix(70)) }
            return value
        }
        let variants = options.map(styled)
        let index = max(0,record.greeting?.count ?? 0) % variants.count
        let selected = variants[index] == record.greeting?.lastText && variants.count > 1
            ? variants[(index+1) % variants.count] : variants[index]
        // Proactive speech has no body cue. In particular, dialogue.greeting and
        // session.enter map to full-body waves that change the prepared framing.
        return DialogueReply(text:selected,eventName:"expression.request",emotion:"joy")
    }
}
