import Foundation
import Security

struct PlatformUser: Codable, Equatable {
    let id, username: String
    let guest: Bool
    var version: Int
    var profile: [String:JSONValue]
    var displayName: String { profile["display_name"]?.string ?? username }
}
struct PlatformSession: Codable, Equatable {
    let token: String
    let expiresAt: String
    var user: PlatformUser
}
/// Preserves unknown server fields across app upgrades and merge patches.
indirect enum JSONValue: Codable, Equatable {
    case object([String:Self]), array([Self]), string(String), number(Double), bool(Bool), null
    init(from decoder:Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String:Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder:Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil();case .bool(let v):try c.encode(v);case .number(let v):try c.encode(v)
        case .string(let v):try c.encode(v);case .object(let v):try c.encode(v);case .array(let v):try c.encode(v) }
    }
    var string:String? { if case .string(let v) = self { return v };return nil }
    var object:[String:Self]? { if case .object(let v) = self { return v };return nil }
    var number:Double? { if case .number(let v) = self { return v };return nil }
    var bool:Bool? { if case .bool(let v) = self { return v };return nil }
    static func encode<T:Encodable>(_ value:T) throws -> Self { try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(value)) }
    func decode<T:Decodable>(_ type:T.Type) throws -> T { try JSONDecoder().decode(type,from:JSONEncoder().encode(self)) }
}
enum PlatformError: LocalizedError {
    case unconfigured, status(Int), keychain, invalidResponse
    var errorDescription:String? {
        switch self {
        case .unconfigured: "账户服务尚未配置。"
        case .status(401): "账号或密码不正确，或登录已过期。"
        case .status(409): "资料已有更新或账号已被使用，请刷新后重试。"
        case .status(429): "操作较频繁，请稍后再试。"
        case .status(422): "请检查填写内容；密码至少 12 位，账号使用字母、数字或下划线。"
        case .status: "暂时连接不上账户服务，本机资料会保留。"
        case .keychain: "登录凭证暂时无法安全保存，请重试。"
        case .invalidResponse: "账户服务返回了无法识别的数据。"
        }
    }
}
private final class PlatformNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class PlatformAPI {
    static let shared = PlatformAPI()
    let baseURL:URL?
    var activeSession:PlatformSession?
    var requiresAccountSession:Bool { baseURL?.scheme == "https" }
    func requiresAuthentication(for accountID:String) -> Bool {
        requiresAccountSession && activeSession?.user.id != accountID
    }
    private let injectedTransport:URLSession?
    private lazy var transport:URLSession = {
        if let injectedTransport{return injectedTransport}
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12;config.timeoutIntervalForResource = 20;config.urlCache = nil
        return URLSession(configuration:config,delegate:PlatformNoRedirect(),delegateQueue:nil)
    }()
    init(baseURL:URL? = nil, transport:URLSession? = nil) {
        struct Connection:Decodable { let baseURL:String }
        let configured = Bundle.main.url(forResource:"PlatformConnection",withExtension:"json")
            .flatMap { try? Data(contentsOf:$0) }.flatMap { try? JSONDecoder().decode(Connection.self,from:$0) }.flatMap { URL(string:$0.baseURL) }
        self.baseURL = baseURL ?? configured
        injectedTransport = transport
    }
    func request(_ method:String,_ path:String,token:String? = nil,body:JSONValue? = nil) async throws -> JSONValue {
        guard let baseURL, baseURL.scheme == "https" || (baseURL.scheme == "http" &&
            (baseURL.host == "127.0.0.1" || baseURL.host?.hasSuffix(".local") == true)),
              path.hasPrefix("/v1/"),let url = URL(string:path,relativeTo:baseURL) else { throw PlatformError.unconfigured }
        var request = URLRequest(url:url);request.httpMethod = method
        if let token { request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization") }
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let body { request.httpBody = try JSONEncoder().encode(body);request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        let (data,response) = try await transport.data(for:request)
        guard let response = response as? HTTPURLResponse else { throw PlatformError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw PlatformError.status(response.statusCode) }
        return try JSONDecoder().decode(JSONValue.self,from:data)
    }
    func aiRequest(accountID:String,path:String) throws -> URLRequest? {
        guard let session=activeSession,session.user.id==accountID else{return nil}
        guard let baseURL,path.hasPrefix("/v1/"),
              baseURL.scheme == "https" || (baseURL.scheme == "http" && (baseURL.host == "127.0.0.1" || baseURL.host?.hasSuffix(".local") == true)),
              let url=URL(string:"/v1/ai/"+path.dropFirst(4),relativeTo:baseURL) else{throw PlatformError.unconfigured}
        var request=URLRequest(url:url);request.setValue("Bearer "+session.token,forHTTPHeaderField:"Authorization")
        return request
    }
    func authenticate(_ action:String,username:String,password:String,name:String,upgrading:PlatformSession?) async throws -> PlatformSession {
        var fields:[String:JSONValue] = ["username":.string(username),"password":.string(password)]
        if action == "register" { fields["display_name"] = .string(name) }
        let data = try await request("POST","/v1/auth/"+action,token:action == "register" && upgrading?.user.guest == true ? upgrading?.token : nil,
                                     body:action == "guest" ? nil : .object(fields))
        let decoder = JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PlatformSession.self,from:JSONEncoder().encode(data))
    }
    /// Prepares content for a future Unity runtime adapter; never substitutes an
    /// unverified download for the currently bundled role.
    func downloadCharacter(_ id:String) async throws -> URL {
        guard let current=activeSession,id.range(of:"^[a-zA-Z0-9_-]{1,120}$",options:.regularExpression) != nil else {throw PlatformError.invalidResponse}
#if targetEnvironment(simulator)
        let platform="ios-simulator"
#else
        let platform="ios"
#endif
        let ticket=try await request("POST","/v1/characters/"+id+"/download?platform="+platform,token:current.token)
        guard activeSession?.user.id==current.user.id,let raw=ticket.object?["manifest"] else {throw CancellationError()}
        let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest=try decoder.decode(CharacterDownloadStore.Manifest.self,from:JSONEncoder().encode(raw))
        guard manifest.characterId==id,manifest.platform==platform else {throw PlatformError.invalidResponse}
        let local=try await CharacterDownloadStore.shared.install(manifest,accountID:current.user.id)
        guard activeSession?.user.id==current.user.id else {throw CancellationError()}
        return local
    }
}
@MainActor enum PlatformCredentials {
    private static let service = "starry.platform.session.v1"
    private static var account: String { PlatformAPI.shared.baseURL?.absoluteString ?? "unconfigured" }
    static func read() -> PlatformSession? {
        var result:CFTypeRef?
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
            kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess,let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PlatformSession.self,from:data)
    }
    static func write(_ value:PlatformSession?) throws {
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        guard let value else { let status = SecItemDelete(query as CFDictionary);guard status == errSecSuccess || status == errSecItemNotFound else { throw PlatformError.keychain };return }
        let data = try JSONEncoder().encode(value)
        let result = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if result == errSecItemNotFound {
            var insert = query;insert[kSecValueData as String] = data;insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary,nil) == errSecSuccess else { throw PlatformError.keychain }
        } else if result != errSecSuccess { throw PlatformError.keychain }
    }
}
