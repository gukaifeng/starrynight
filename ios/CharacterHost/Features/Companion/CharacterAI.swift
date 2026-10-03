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
    var preparedClips:[AIPreparedClip]?
}
struct AIPreparedClip:Decodable,Sendable {
    var id:String
    var script:AIScript
    var audio:[AIPreparedAudio]
}
struct AIPreparedAudio:Decodable,Sendable {var beatId:String;var data:String}

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
    var coreStreaming:Bool?
    var coreComplete:Bool?
    var traceId:String?
    var serverAtMs:Double?
    var trace:VoiceServerTrace?
    var receivedAt:Double?
}
struct AIReactionPoolStatus:Decodable,Sendable {
    var capacity:Int
    var ready:[String:Int]
    var preparing:Bool
    var kinds:[String:String]
    var preparedClips:[AIPreparedClip]?
}
private struct AIReactionPause:Decodable,Sendable {var paused:Bool}
enum AIConnectionError: LocalizedError {
    case unconfigured, unavailable, server(Int), remote(String), network(Int), invalidResponse, testingDisabled, authenticationRequired
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "登录星夜后，就可以继续聊天了。"
        case .unconfigured: "AI 连接尚未配置。"
        case .unavailable: "暂时连不上 AI 服务，请检查网络后重试。"
        case .invalidResponse: "AI 服务返回的数据格式异常，自动恢复仍未成功。点消息旁的感叹号可重发。"
        case .network(let code): Self.networkDescription(code)
        case .server(let code): code == 401 ? "登录已过期，请重新登录后重发消息。" : [429,503].contains(code) ? "AI 服务暂时繁忙，重试后仍未恢复。点消息旁的感叹号可重发。" : "AI 服务返回异常响应（HTTP \(code)），重试后仍未完成。点消息旁的感叹号可重发。"
        case .remote(let code): Self.remoteDescription(code)
        case .testingDisabled: "自动测试已关闭付费 AI 调用。"
        }
    }
    var canRetry:Bool {
        switch self {
        case .unavailable,.network,.invalidResponse:return true
        case .server(let code):return [408,409,429,500,502,503,504].contains(code)
        case .remote(let code):return ["SERVER_BUSY","TURN_IN_PROGRESS","TURN_CLEANUP_TIMEOUT","STREAM_INTERRUPTED","REQUEST_INCOMPLETE","REPLY_TIMEOUT","CONNECTION_FAILED","PROVIDER_TIMEOUT","STRUCTURE_INVALID","REPLY_UNAVAILABLE","STREAM_INCOMPLETE"].contains(code) || code.hasPrefix("PROVIDER_429_") || code.hasPrefix("PROVIDER_5")
        default:return false
        }
    }
    static func networkDescription(_ code:Int)->String {
        switch code {
        case URLError.notConnectedToInternet.rawValue:return "当前设备没有网络连接。恢复网络后，点消息旁的感叹号重发。"
        case URLError.timedOut.rawValue:return "连接 AI 服务超时，重试后仍未收到完整响应。点消息旁的感叹号可重发。"
        case URLError.networkConnectionLost.rawValue:return "与 AI 服务的网络连接中断，重连仍未完成。点消息旁的感叹号可重发。"
        case URLError.secureConnectionFailed.rawValue,URLError.serverCertificateUntrusted.rawValue:return "无法建立安全连接，请检查设备日期、网络或服务器证书。"
        default:return "无法连接 AI 服务（网络错误 \(code)），重试后仍未恢复。点消息旁的感叹号可重发。"
        }
    }
    private static func remoteDescription(_ code:String)->String {
        switch code {
        case "TURN_IN_PROGRESS": return "这条消息正在生成回复。"
        case "SERVER_BUSY": return "AI 服务暂时繁忙，请稍后重试。"
        case "TURN_CLEANUP_TIMEOUT": return "AI 连接正在恢复，请重试。"
        case "DAILY_CALL_LIMIT","USAGE_LIMIT_TTS","USAGE_LIMIT_ASR": return "AI 服务仍在使用旧版测试额度设置，请更新本机服务。"
        case "REPLY_TIMEOUT": return "这次回复等待过久，可以重新发送。"
        case "STREAM_INTERRUPTED","STREAM_INCOMPLETE","REQUEST_INCOMPLETE": return "AI 响应在传输中中断，自动恢复仍未成功。点消息旁的感叹号可重发。"
        case "STRUCTURE_INVALID","STREAM_CONTENT_INVALID","STREAM_JSON_INVALID","STREAM_SPEECH_INVALID":return "AI 返回的回复格式异常，自动修复仍未成功。点消息旁的感叹号可重发。"
        case "REPLY_UNAVAILABLE":return "AI 多次生成了重复内容，重新生成仍未通过检查。点消息旁的感叹号可重发。"
        case "CONNECTION_FAILED","PROVIDER_TIMEOUT":return "服务器连接 AI 服务商超时或中断，重试后仍未恢复。点消息旁的感叹号可重发。"
        default:
            if code.hasPrefix("PROVIDER_429_") {return "AI 服务暂时繁忙，请稍后重试。"}
            if code.hasPrefix("PROVIDER_403_") {return "AI 服务商拒绝了请求，请检查模型权限或账户余额（\(code)）。"}
            if code.hasPrefix("PROVIDER_401_") {return "AI 服务商的认证已失效，需要管理员更新连接配置。"}
            return "AI 服务未能完成这次请求（\(code)）。点消息旁的感叹号可重发。"
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
    func urlSession(_ session:URLSession,task:URLSessionTask,didFinishCollecting metrics:URLSessionTaskMetrics) {
        guard let id=task.originalRequest?.value(forHTTPHeaderField:"X-Starry-Voice-Trace") else {return}
        let origin=metrics.taskInterval.start
        var spans:[VoiceSpan]=[]
        var reused=false
        for (index,metric) in metrics.transactionMetrics.enumerated() {
            reused = reused || metric.isReusedConnection
            for (name,start,end) in [("network.dns",metric.domainLookupStartDate,metric.domainLookupEndDate),
                ("network.tcp",metric.connectStartDate,metric.connectEndDate),("network.tls",metric.secureConnectionStartDate,metric.secureConnectionEndDate),
                ("network.upload",metric.requestStartDate,metric.requestEndDate),("network.response_wait",metric.requestEndDate,metric.responseStartDate),
                ("network.download",metric.responseStartDate,metric.responseEndDate)] {
                if let start,let end {spans.append(VoiceSpan(name:name,startMs:max(0,start.timeIntervalSince(origin)*1000),durationMs:max(0,end.timeIntervalSince(start)*1000),beatId:"transaction-\(index)"))}
            }
        }
        let values=spans;let connection=reused
        Task { @MainActor in
            let offset=VoiceTimeline.shared.records.last(where:{$0.id==id})?.marks["request_sent"] ?? 0
            for var value in values {value.startMs+=offset;VoiceTimeline.shared.add(id,value)}
            VoiceTimeline.shared.flag(id,"connection_reused",connection ? "是；DNS/TLS 可能没有本次耗时" : "否")
        }
    }
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
        guard ModelDescriptor.all.first(where:{$0.id==characterID})?.isPreviewOnly != true else {throw AIConnectionError.testingDisabled}
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
        let data:Data,response:URLResponse
        do {(data,response)=try await session.data(for:request)}
        catch let error as URLError {if Task.isCancelled {throw CancellationError()};throw AIConnectionError.network(error.code.rawValue)}
        guard (response as? HTTPURLResponse)?.statusCode==200 else {
            throw AIConnectionError.http((response as? HTTPURLResponse)?.statusCode ?? 0,body:data)
        }
        let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self,from:data)
    }
    func translate(messageID:UUID,segments:[TranslationSegment],to language:AppLanguage,sourceKind:String="assistant",optionID:String?=nil) async throws -> TranslationResponse {
        var request=try request("/v1/conversations/"+characterID+"/messages/"+messageID.uuidString+"/translation")
        request.httpMethod="POST";request.timeoutInterval=30
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var body:[String:Any]=["target_language":language.rawValue,"source_kind":sourceKind,
            "segments":segments.map {["id":$0.id,"kind":$0.kind,"text":$0.text]}]
        if let optionID {body["option_id"]=optionID}
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
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
        guard Self.paidTestsEnabled else {return} // Ordinary UI tests never call the cloud.
#if DEBUG && targetEnvironment(simulator)
        if ConversationContinuityFixture.enabled {return}
#endif
        guard let id=script.openingID else {return}
        struct Acknowledgement:Decodable,Sendable {let accepted:Bool}
        let _:Acknowledgement=try await configuration("/v1/conversations/"+characterID+"/opening",body:[
            "opening_id":id,"message_id":script.messageId,"conversation_reset":resetID])
    }
    func events(path: String, body: [String:Any]?, traceID:String?=nil,consume: (AIEvent) async throws -> Void) async throws {
#if DEBUG && targetEnvironment(simulator)
        if ConversationContinuityFixture.enabled {
            try await ConversationContinuityFixture.events(characterID:characterID,body:body,consume:consume);return
        }
#endif
        var request = try request(path); request.httpMethod = "POST"
        let timeline=VoiceTimeline.shared
        let traceID=traceID ?? timeline.begin(account:accountID,character:characterID,kind:path.hasSuffix("/audio") ? "replay" : body?["trigger"] as? String ?? "reply")
        request.setValue(traceID,forHTTPHeaderField:"X-Starry-Voice-Trace")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
        // Older gateways ignore this header and keep their original event order.
        request.setValue("timeline-v2",forHTTPHeaderField:"X-Starry-Reply-Mode")
        request.setValue("parallel-v1",forHTTPHeaderField:"X-Starry-Performance-Mode")
        let encoding=timeline.now(traceID)
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject:body) }
        timeline.span(traceID,"request.encode",start:encoding)
        let cancellation=AIStreamCancellation()
        let networkStart=timeline.now(traceID)
        defer {timeline.span(traceID,"network.stream",start:networkStart)}
        do {
          try await withTaskCancellationHandler {
            let headers=timeline.now(traceID);timeline.mark(traceID,"request_sent")
            let (bytes, response) = try await session.bytes(for:request)
            timeline.span(traceID,"http.headers_wait",start:headers)
            timeline.mark(traceID,"response_headers")
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
                let decoding=timeline.now(traceID)
                var event = try decoder.decode(AIEvent.self,from:Data(line.dropFirst(6).utf8))
                event.traceId=traceID;event.receivedAt=ProcessInfo.processInfo.systemUptime
                timeline.span(traceID,"sse.decode",start:decoding,bytes:line.utf8.count)
                timeline.receive(traceID,event:event)
                if event.type == "reply.error" { throw AIConnectionError.remote(event.code ?? "ERROR") }
                if event.type == "reply.completed" || (path.hasSuffix("/audio") && ["segment.audio.ready","audio.error"].contains(event.type)) { completed = true }
                let consuming=timeline.now(traceID)
                try await consume(event)
                timeline.span(traceID,"sse.consume",start:consuming,beat:event.beatId)
            }
            guard completed else { throw AIConnectionError.remote("STREAM_INTERRUPTED") }
            timeline.mark(traceID,"network_complete")
          } onCancel: { cancellation.cancel() }
        } catch is CancellationError {timeline.finish(traceID,status:"cancelled");throw CancellationError() }
        catch let error as AIConnectionError {timeline.flag(traceID,"error_type","AIConnectionError");if case .remote(let code)=error {timeline.flag(traceID,"error_code",code)};timeline.finish(traceID,status:"failed");throw error }
        catch {timeline.flag(traceID,"error_type",String(describing:type(of:error)));timeline.finish(traceID,status:Task.isCancelled ? "cancelled" : "failed");if Task.isCancelled { throw CancellationError() };if let error=error as? URLError {throw AIConnectionError.network(error.code.rawValue)};throw AIConnectionError.invalidResponse }
    }
    func socket(nickname: String,traceID:String?=nil) throws -> URLSessionWebSocketTask {
        var request = try request("/v1/asr/" + characterID)
        var parts = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.queryItems = [URLQueryItem(name:"nickname",value:nickname)]
        request.url = parts.url
        if let traceID {request.setValue(traceID,forHTTPHeaderField:"X-Starry-Voice-Trace")}
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
