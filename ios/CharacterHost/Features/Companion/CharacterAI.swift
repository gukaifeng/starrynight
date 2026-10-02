import Foundation
struct ConversationResetReceipt:Decodable,Sendable {
    let resetID:String
    let version:Int
    enum CodingKeys:String,CodingKey {case resetID="reset_id",version}
}
struct AIQuickReply:Decodable,Identifiable {
    let id:String
    let text:String
    let likelihood:Double
}
struct AIQuickReplySet:Decodable {
    let sourceMessageId:String
    let options:[AIQuickReply]
    let preparing:Bool
}

struct AIScript: Codable, Sendable {
    var messageId: String
    var characterId: String
    var text: String
    var beats: [AIBeat]
    var idleDecision: String?
    var memorySuggestions: [String]?
    var openingID: String? = nil
    var goalState: ConversationGoals? = nil
}
struct AIBeat: Codable, Sendable, Identifiable {
    var beatId: String
    var thought: String?
    var dialogue: AIDialogue?
    var narrations: [AINarration]
    var visuals: [AIVisual]
    var duration: Double?
    var vocalEvents: [AIVocalEvent]?
    var parts: [AIReplyPart]? = nil
    var readingDuration: Double? = nil
    var id: String { beatId }
    var hasAudio: Bool { dialogue != nil || !(vocalEvents ?? []).isEmpty }
    var visibleNarrations:[AINarration] {narrations.filter(\.isVisible)}
    var visibleThought: String? {
        Self.visibleThought(thought)
    }
    static func visibleThought(_ thought:String?)->String? {
        guard let thought else { return nil }
        let text=thought.trimmingCharacters(in:.whitespacesAndNewlines)
        // Same contract as schemas.visible_thought, including old local records.
        // Omitting an invalid optional aside never changes dialogue or audio.
        let english=text.range(of:#"\b(?:I|my|we|our)\b"#,options:[.regularExpression,.caseInsensitive]) != nil
            && text.range(of:#"[\u3400-\u9fff\u3040-\u30ff]"#,options:.regularExpression) == nil
        if english {
            guard text.unicodeScalars.count<=96,text.split(whereSeparator:{$0.isWhitespace}).count<=12,
                  text.range(of:#"\b(?:user|prompt|dialogue|response strategy|as a character|should respond|need to reply|must answer|system|instruction)\b"#,options:[.regularExpression,.caseInsensitive]) == nil else {return nil}
        } else {
            guard !text.isEmpty,text.unicodeScalars.count<=40,text.contains("我") || text.contains("咱") else {return nil}
        }
        let metadata = ["用户","让对方","对方感受","需传递","正式问候","边界清晰","回应策略",
                        "准备回复","作为角色","符合人设","需要表现","应当表达","台词","情绪状态","遵守",
                        "编排","提示词","分享邀请","回复意图"]
        let planning = ["(?:引出|引导|转入|转向|延续|承接).{0,18}(?:话题|邀请)",
                        "(?:营造|延续|保持|维持|烘托|渲染).{0,18}氛围",
                        "(?:结合|根据|符合|体现).{0,14}(?:人设|设定|偏好|上下文)",
                        "(?:选择|使用|采用).{0,18}(?:语气|措辞|表情|动作)"]
        return metadata.contains(where:text.contains) || planning.contains(where:{text.range(of:$0,options:.regularExpression) != nil}) ? nil : text
    }
}
struct AIReplyPart: Codable, Sendable {
    var kind: String
    var text: String
    var at: Double
    var isVisible: Bool {
        if kind == "thought" {return AIBeat.visibleThought(text) != nil}
        return (kind == "dialogue" || kind == "narration") && !text.isEmpty && at.isFinite && (0...1).contains(at)
    }
}
struct AIDialogue: Codable, Sendable { var text: String }
struct AIVocalEvent: Codable, Sendable { var event: String }
struct AINarration: Codable, Sendable {
    var text: String; var mode: String; var grounding: String
    var isVisible:Bool {mode=="performed" || text.range(of:"头发|发色|长发|短发|棕色|金色|肤色|皮肤|眼睛|瞳孔|眼眸|身材|脸型|衣服|裙子|穿着|留着|一双|外貌",options:.regularExpression)==nil}
}
struct AIVisual: Codable, Sendable {
    var assetId: String; var group: String; var durationMs: Int; var grounding: String
    var offsetMs:Int? = nil
    var active:Bool? = nil
}
struct AIEvent: Decodable, Sendable {
    var type: String
    var script: AIScript?
    var beatId: String?
    var messageId: String?
    var data: String?
    var duration: Double?
    var code: String?
    var message: String?
    var text: String?
    var visuals: [AIVisual]?
    var prepared: Bool?
    var preparationInflight:Bool?
}
struct AIReactionPoolStatus:Decodable,Sendable {
    var capacity:Int
    var ready:[String:Int]
    var preparing:Bool
    var kinds:[String:String]
}
private struct AIReactionPause:Decodable,Sendable {var paused:Bool}
enum AIConnectionError: LocalizedError {
    case unconfigured, unavailable, server(Int), remote(String), testingDisabled, authenticationRequired
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "登录星夜后，就可以继续聊天了。"
        case .unconfigured: "AI 连接尚未配置。"
        case .unavailable: "暂时连不上 AI 服务，请检查网络后重试。"
        case .server(let code): code == 401 ? "AI 连接凭证已变更，请更新安装版本。" : [429,503].contains(code) ? "AI 服务暂时繁忙，请稍后重试。" : "AI 服务暂时不可用（\(code)）。"
        case .remote(let code): Self.remoteDescription(code)
        case .testingDisabled: "自动测试已关闭付费 AI 调用。"
        }
    }
    private static func remoteDescription(_ code:String)->String {
        switch code {
        case "TURN_IN_PROGRESS": return "这条消息正在生成回复。"
        case "SERVER_BUSY": return "AI 服务暂时繁忙，请稍后重试。"
        case "TURN_CLEANUP_TIMEOUT": return "AI 连接正在恢复，请重试。"
        case "DAILY_CALL_LIMIT","USAGE_LIMIT_TTS","USAGE_LIMIT_ASR": return "AI 服务仍在使用旧版测试额度设置，请更新本机服务。"
        case "REQUEST_INCOMPLETE": return "这次回复已中断，可以重新发送。"
        case "REPLY_TIMEOUT": return "这次回复等待过久，可以重新发送。"
        default:
            if code.hasPrefix("PROVIDER_429_") {return "AI 服务暂时繁忙，请稍后重试。"}
            return "AI 暂时没有完成回复，请稍后重试。"
        }
    }
    static func http(_ status:Int,body:Data)->AIConnectionError {
        if status==401 {return .server(status)}
        if let json=(try? JSONSerialization.jsonObject(with:body)) as? [String:Any],let code=json["detail"] as? String {
            return .remote(code)
        }
        return .server(status)
    }
}

/// Task cancellation can occur while the consumer is waiting for audio to play,
/// with no pending URLSession read. Cancel the transport immediately in that case.
private final class AIStreamCancellation: @unchecked Sendable {
    private let lock=NSLock()
    private var task:URLSessionTask?
    private var cancelled=false
    func install(_ value:URLSessionTask) {
        lock.lock();let stop=cancelled;if !stop {task=value};lock.unlock()
        if stop {value.cancel()}
    }
    func cancel() {
        lock.lock();cancelled=true;let value=task;task=nil;lock.unlock()
        value?.cancel()
    }
}
private final class AINoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class CharacterAI {
    /// Installed by the account layer; the AI pipeline itself stays independent
    /// of login UI and the account persistence implementation.
    static var authenticatedRequest: ((String,String) throws -> URLRequest?)?
    static var authenticationRequired: ((String) -> Bool)?
    var requiresAuthentication:Bool { Self.authenticationRequired?(accountID) == true }
    static var clearAccountArchive: ((String,String) async throws -> Void)?
    static var deleteAccountConversation: ((String,String,String) async throws -> Int)?
    private struct Connection: Decodable { let baseURL, clientToken: String }
    private let connection: Connection?
    let accountID: String
    let characterID: String
    private let installation: String
    private let session: URLSession
    init(accountID: String, characterID: String) {
        self.accountID = accountID; self.characterID = characterID
        if let url = Bundle.main.url(forResource:"Connection",withExtension:"json"), let data = try? Data(contentsOf:url) {
            connection = try? JSONDecoder().decode(Connection.self,from:data)
        } else { connection = nil }
        if let value = UserDefaults.standard.string(forKey:"starry.ai.installation") { installation = value }
        else { installation = UUID().uuidString; UserDefaults.standard.set(installation,forKey:"starry.ai.installation") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 85; config.timeoutIntervalForResource = 180
        config.urlCache = nil; config.waitsForConnectivity = false
        session = URLSession(configuration:config,delegate:AINoRedirect(),delegateQueue:nil)
    }
    static var paidTestsEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        let automation = args.contains { $0.hasPrefix("--") && ($0.contains("testing") || $0.hasSuffix("-check") || $0.contains("fixture")) }
        return !automation || args.contains("--live-ai")
    }
    static var reactionPreparationEnabled:Bool {
        let args=ProcessInfo.processInfo.arguments
        let automation=args.contains { $0.hasPrefix("--") && ($0.contains("testing") || $0.hasSuffix("-check") || $0.contains("fixture")) }
        return !automation || (args.contains("--live-ai") && args.contains("--live-reaction-prewarm"))
    }
    static var smartReplyPreparationEnabled:Bool {
        let args=ProcessInfo.processInfo.arguments
        let automation=args.contains {$0.hasPrefix("--") && ($0.contains("testing") || $0.hasSuffix("-check") || $0.contains("fixture"))}
        return !automation || (args.contains("--live-ai") && args.contains("--live-smart-replies"))
    }
    func quickReplies(_ body:[String:Any],prepare:Bool) async throws -> AIQuickReplySet {
        guard Self.smartReplyPreparationEnabled else {throw AIConnectionError.testingDisabled}
        return try await configuration("/v1/conversations/"+characterID+"/suggestions/"+(prepare ? "prepare" : "status"),body:body)
    }
    func prepareReactions(_ body:[String:Any]) async throws -> AIReactionPoolStatus {
        guard Self.reactionPreparationEnabled else {throw AIConnectionError.testingDisabled}
        return try await configuration("/v1/conversations/"+characterID+"/reactions/prepare",body:body)
    }
    func reactionStatus(_ body:[String:Any]) async throws -> AIReactionPoolStatus {
        try await configuration("/v1/conversations/"+characterID+"/reactions/status",body:body)
    }
    func pauseReactions(_ body:[String:Any]) async {
        let _:AIReactionPause? = try? await configuration("/v1/conversations/"+characterID+"/reactions/pause",body:body)
    }
    func request(_ path: String, paid: Bool = true) throws -> URLRequest {
        if paid && !Self.paidTestsEnabled { throw AIConnectionError.testingDisabled }
        if let request = try Self.authenticatedRequest?(accountID,path) { return request }
        if requiresAuthentication { throw AIConnectionError.authenticationRequired }
        guard let connection, let base = URL(string:connection.baseURL),
              base.scheme == "https" || (base.scheme == "http" && (base.host?.hasSuffix(".local") == true || base.host == "127.0.0.1")),
              let url = URL(string:path,relativeTo:base)?.absoluteURL else { throw AIConnectionError.unconfigured }
        var request = URLRequest(url:url)
        request.setValue("Bearer " + connection.clientToken,forHTTPHeaderField:"Authorization")
        request.setValue(installation,forHTTPHeaderField:"X-Starry-Installation")
        request.setValue(accountID,forHTTPHeaderField:"X-Starry-Account")
        return request
    }
    func check() async -> Bool {
        guard let request = try? request("/v1/status",paid:false),
              let (_, response) = try? await session.data(for:request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
    func configuration<T:Decodable & Sendable>(_ path:String,body:[String:Any]? = nil) async throws -> T {
        var request=try request(path,paid:false);request.timeoutInterval=15
        request.setValue("timeline-v2",forHTTPHeaderField:"X-Starry-Reply-Mode")
        request.setValue("parallel-v1",forHTTPHeaderField:"X-Starry-Performance-Mode")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let body {
            request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody=try JSONSerialization.data(withJSONObject:body)
        }
        let (data,response)=try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200 else {
            throw AIConnectionError.http((response as? HTTPURLResponse)?.statusCode ?? 0,body:data)
        }
        let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self,from:data)
    }
    func translate(messageID:UUID,segments:[TranslationSegment],to language:AppLanguage) async throws -> TranslationResponse {
        var request=try request("/v1/conversations/"+characterID+"/messages/"+messageID.uuidString+"/translation")
        request.httpMethod="POST";request.timeoutInterval=30
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["target_language":language.rawValue,
            "segments":segments.map {["id":$0.id,"kind":$0.kind,"text":$0.text]}])
        let (data,response)=try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200 else {throw AIConnectionError.http((response as? HTTPURLResponse)?.statusCode ?? 0,body:data)}
        let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TranslationResponse.self,from:data)
    }
    func clearMessages() async throws {
        var request = try request("/v1/conversations/"+characterID+"/messages",paid:false)
        request.httpMethod = "DELETE"
        let (_,response) = try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIConnectionError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        try await Self.clearAccountArchive?(accountID,characterID)
    }
    func deleteConversation(resetID:String) async throws -> ConversationResetReceipt {
        // PostgreSQL assigns the authoritative monotonic epoch for signed-in
        // accounts. The worker rejects a delayed older reset from another device.
        let version=try await Self.deleteAccountConversation?(accountID,characterID,resetID) ?? 0
        try Task.checkCancellation()
        var request=try request("/v1/conversations/"+characterID+"?reset_id="+resetID+"&reset_version=\(version)",paid:false)
        request.httpMethod="DELETE";request.timeoutInterval=20
        let (data,response)=try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200 else {
            throw AIConnectionError.http((response as? HTTPURLResponse)?.statusCode ?? 0,body:data)
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode(ConversationResetReceipt.self,from:data)
    }
    func registerOpening(_ script:AIScript,resetID:String) async throws {
#if DEBUG && targetEnvironment(simulator)
        if ConversationContinuityFixture.enabled {return}
#endif
        guard let id=script.openingID else {return}
        struct Acknowledgement:Decodable,Sendable {let accepted:Bool}
        let _:Acknowledgement=try await configuration("/v1/conversations/"+characterID+"/opening",body:[
            "opening_id":id,"message_id":script.messageId,"conversation_reset":resetID])
    }
    func events(path: String, body: [String:Any]?, consume: (AIEvent) async throws -> Void) async throws {
#if DEBUG && targetEnvironment(simulator)
        if ConversationContinuityFixture.enabled {
            try await ConversationContinuityFixture.events(characterID:characterID,body:body,consume:consume);return
        }
#endif
        var request = try request(path); request.httpMethod = "POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
        // Older gateways ignore this header and keep their original event order.
        request.setValue("timeline-v2",forHTTPHeaderField:"X-Starry-Reply-Mode")
        request.setValue("parallel-v1",forHTTPHeaderField:"X-Starry-Performance-Mode")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject:body) }
        let cancellation=AIStreamCancellation()
        do {
          try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for:request)
            cancellation.install(bytes.task)
            defer { cancellation.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                var errorBody=Data()
                for try await byte in bytes { if errorBody.count>=16384 {break};errorBody.append(byte) }
                throw AIConnectionError.http((response as? HTTPURLResponse)?.statusCode ?? 0,body:errorBody)
            }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            var completed = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data: ") else { continue }
                guard line.utf8.count < 512*1024 else { throw AIConnectionError.remote("EVENT_TOO_LARGE") }
                let event = try decoder.decode(AIEvent.self,from:Data(line.dropFirst(6).utf8))
                if event.type == "reply.error" { throw AIConnectionError.remote(event.code ?? "ERROR") }
                if event.type == "reply.completed" || (path.hasSuffix("/audio") && ["segment.audio.ready","audio.error"].contains(event.type)) { completed = true }
                try await consume(event)
            }
            guard completed else { throw AIConnectionError.remote("STREAM_INTERRUPTED") }
          } onCancel: { cancellation.cancel() }
        } catch is CancellationError { throw CancellationError() }
        catch let error as AIConnectionError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw AIConnectionError.unavailable }
    }
    func socket(nickname: String) throws -> URLSessionWebSocketTask {
        var request = try request("/v1/asr/" + characterID)
        var parts = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.queryItems = [URLQueryItem(name:"nickname",value:nickname)]
        request.url = parts.url
        return session.webSocketTask(with:request)
    }
}

/// Network delivery must not wait for PCM to finish playing. This bounded,
/// turn-owned queue preserves audio order while visual events arrive in parallel.
@MainActor final class ReplyAudioPump {
    private let continuation: AsyncThrowingStream<AIEvent,Error>.Continuation
    private var worker: Task<Void,Error>?
    private var failure: Error?
    init(receive: @escaping @MainActor (AIEvent) async throws -> Void) {
        let pair = AsyncThrowingStream<AIEvent,Error>.makeStream(bufferingPolicy:.bufferingOldest(128))
        continuation=pair.continuation
        worker=Task { @MainActor [weak self] in
            do {
                for try await event in pair.stream {
                    try Task.checkCancellation()
                    try await receive(event)
                }
            } catch { self?.failure=error; throw error }
        }
    }
    func send(_ event:AIEvent) throws {
        if let failure {throw failure}
        switch continuation.yield(event) {
        case .enqueued: break
        case .dropped: throw AIConnectionError.remote("AUDIO_QUEUE_FULL")
        case .terminated: throw CancellationError()
        @unknown default: throw CancellationError()
        }
    }
    func finish() async throws {continuation.finish();try await worker?.value}
    func cancel() {continuation.finish(throwing:CancellationError());worker?.cancel()}
}
