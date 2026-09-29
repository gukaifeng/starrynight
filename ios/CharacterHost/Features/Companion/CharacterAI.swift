import Foundation

struct AIScript: Codable, Sendable {
    var messageId: String
    var characterId: String
    var text: String
    var beats: [AIBeat]
    var idleDecision: String?
    var memorySuggestions: [String]?
}
struct AIBeat: Codable, Sendable, Identifiable {
    var beatId: String
    var thought: String?
    var dialogue: AIDialogue?
    var narrations: [AINarration]
    var visuals: [AIVisual]
    var duration: Double?
    var vocalEvents: [AIVocalEvent]?
    var id: String { beatId }
    var hasAudio: Bool { dialogue != nil || !(vocalEvents ?? []).isEmpty }
    var visibleThought: String? {
        guard let thought, !thought.isEmpty else { return nil }
        // Also protect old persisted replies from the first integration build.
        let metadata = ["用户","让对方","对方感受","需传递","正式问候","边界清晰","回应策略",
                        "准备回复","作为角色","符合人设","需要表现","应当表达","台词","情绪状态","遵守"]
        return metadata.contains(where:thought.contains) ? nil : thought
    }
}
struct AIDialogue: Codable, Sendable { var text: String }
struct AIVocalEvent: Codable, Sendable { var event: String }
struct AINarration: Codable, Sendable { var text: String; var mode: String; var grounding: String }
struct AIVisual: Codable, Sendable { var assetId: String; var group: String; var durationMs: Int; var grounding: String }
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
}
enum AIConnectionError: LocalizedError {
    case unconfigured, unavailable, server(Int), remote(String), testingDisabled
    var errorDescription: String? {
        switch self {
        case .unconfigured: "AI 连接尚未配置。"
        case .unavailable: "暂时连不上 AI 服务。当前开发版需要 Mac 上的服务运行，并处于同一网络。"
        case .server(let code): code == 401 ? "AI 连接凭证已变更，请更新安装版本。" : code == 409 ? "上一轮还在结束，请稍后再试。" : "AI 服务暂时不可用（\(code)）。"
        case .remote(let code): code.contains("LIMIT") ? "本机设置的今日 AI 用量已用完，稍后再聊。" : "AI 暂时没有完成回复，请稍后重试。"
        case .testingDisabled: "自动测试已关闭付费 AI 调用。"
        }
    }
}
private final class AINoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class CharacterAI {
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
    func request(_ path: String, paid: Bool = true) throws -> URLRequest {
        if paid && !Self.paidTestsEnabled { throw AIConnectionError.testingDisabled }
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
    func clearMessages() async throws {
        var request = try request("/v1/conversations/"+characterID+"/messages",paid:false)
        request.httpMethod = "DELETE"
        let (_,response) = try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIConnectionError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
    func events(path: String, body: [String:Any]?, consume: (AIEvent) async throws -> Void) async throws {
        var request = try request(path); request.httpMethod = "POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject:body) }
        do {
            let (bytes, response) = try await session.bytes(for:request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AIConnectionError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
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
