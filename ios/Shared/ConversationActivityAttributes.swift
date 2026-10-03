import ActivityKit
import Foundation

/// Versioned, small presentation data shared by the app and its isolated widget.
/// No account IDs, credentials, full transcript, or model resources cross here.
struct ConversationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Sendable { case thinking, speaking, ready, paused }
        var phase: Phase
        var language: String
        var emotion: String
        var preview: String?
        var playbackStart: Date?
        var playbackEnd: Date?
        var messageID: String?
    }
    let version: Int
    let turnID: String
    let characterID: String
    let characterName: String
    let avatarAsset: String

    static func route(characterID:String,messageID:String?=nil)->URL? {
        var url=URLComponents();url.scheme="starrynight";url.host="conversation"
        url.queryItems=[URLQueryItem(name:"character",value:characterID)]
        if let messageID {url.queryItems?.append(.init(name:"message",value:messageID))}
        return url.url
    }
    static func decodeRoute(_ url:URL)->(character:String,message:UUID?)? {
        guard url.scheme=="starrynight",url.host=="conversation",let parts=URLComponents(url:url,resolvingAgainstBaseURL:false),
              let role=parts.queryItems?.first(where:{$0.name=="character"})?.value,!role.isEmpty,role.count<=128,
              role.allSatisfy({$0.isLetter || $0.isNumber || "-_.".contains($0)}) else {return nil}
        return (role,parts.queryItems?.first(where:{$0.name=="message"})?.value.flatMap(UUID.init(uuidString:)))
    }
}

enum ConversationIslandCopy {
    static func text(_ key:String,language:String)->String {
        let en=language=="en",trad=language=="zh-Hant"
        switch key {
        case "thinking":return en ? "Finding the right words" : trad ? "正在想怎麼回答你" : "正在想怎么回答你"
        case "speaking":return en ? "A voice by your side" : trad ? "正在輕聲對你說" : "正在轻声对你说"
        case "ready":return en ? "Your reply is here" : trad ? "這句話，留給你" : "这句话，留给你"
        case "paused":return en ? "Voice paused · tap to return" : trad ? "聲音已暫停，點開繼續" : "声音已暂停，点开继续"
        case "stale":return en ? "Open to continue" : trad ? "回到星夜，接著聊" : "回到星夜，接着聊"
        case "open":return en ? "Continue chatting" : trad ? "回去接著聊" : "回去接着聊"
        default:return en ? "StarryNight" : "星夜"
        }
    }
    static func symbol(_ state:ConversationActivityAttributes.ContentState)->String {
        if state.phase == .thinking {return "ellipsis"}
        if state.phase == .paused {return "pause.fill"}
        if state.phase == .ready {return "checkmark"}
        return ["happy","affectionate","playful"].contains(state.emotion) ? "heart.fill" : "waveform"
    }
}
