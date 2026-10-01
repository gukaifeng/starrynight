import Foundation
import Observation

@MainActor @Observable
final class AccountStore {
    private(set) var session: DemoAccountSession?
    var error: String?
    private(set) var cloudSession: PlatformSession?
    var isBusy = false
    var syncStatus = "本机保存"
    var cloudShouldImportLocal = false
    var onSync: (() -> Void)?
    var onUseCloud: (() -> Void)?
    var onFirstSync: (() -> Void)?
    var hasSyncConflicts = false
    var needsReauthentication = false
    @ObservationIgnored private var isolatedTest = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sessionKey: String
    var isSignedIn: Bool { session != nil }
    func updateCloudProfile(version:Int,profile:[String:JSONValue]) {
        guard var remote = cloudSession else { return }
        remote.user.version = version; remote.user.profile = profile
        cloudSession = remote; PlatformAPI.shared.activeSession = remote
        if !isolatedTest { do { try PlatformCredentials.write(remote) } catch { self.error = error.localizedDescription } }
    }

    init(defaults:UserDefaults = .standard, arguments:[String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        CharacterAI.authenticatedRequest = { account,path in try PlatformAPI.shared.aiRequest(accountID:account,path:path) }
        CharacterAI.clearAccountArchive = { account,character in
            guard let remote=PlatformAPI.shared.activeSession,remote.user.id==account else{return}
            _ = try await PlatformAPI.shared.request("DELETE","/v1/conversations/"+character+"/messages",token:remote.token)
        }
        CharacterAI.deleteAccountConversation = { account,character,reset in
            guard let remote=PlatformAPI.shared.activeSession,remote.user.id==account else{return 0}
            let receipt=try await PlatformAPI.shared.request("DELETE","/v1/conversations/"+character+"?reset_id="+reset,token:remote.token)
            return Int(receipt.object?["version"]?.number ?? 0)
        }
        isolatedTest = arguments.contains("--ui-testing") || defaults != .standard
        CharacterAI.authenticationRequired = { account in
            !arguments.contains("--ui-testing") && PlatformAPI.shared.requiresAuthentication(for:account)
        }
        var key = "xiaoban.demo-account.v1"
#if DEBUG
        // Existing viewer/voice tests exercise their own flows with an isolated demo session.
        // Auth tests explicitly use the real login gate. Neither path touches the user's session.
        if arguments.contains("--ui-testing") { key += ".qa" }
        if (arguments.contains("--auth-testing") && !arguments.contains("--keep-auth-data")) || (arguments.contains("--companion-testing") && !arguments.contains("--keep-companion-data")) {
            defaults.removeObject(forKey:key)
        }
#endif
        sessionKey = key
        if (isolatedTest || !PlatformAPI.shared.requiresAccountSession), let data = defaults.data(forKey:key),
           let saved = try? JSONDecoder().decode(DemoAccountSession.self,from:data),[DemoAccount.id,DemoAccount.alternateID].contains(saved.accountID) {
            session = saved
        }
#if DEBUG
        if arguments.contains("--ui-testing") && !arguments.contains("--auth-testing") && session == nil {
            session = DemoAccountSession(accountID:DemoAccount.id,method:.wechat)
        }
#endif
        if !isolatedTest, let saved = PlatformCredentials.read() {
            cloudSession = saved; PlatformAPI.shared.activeSession = saved
            session = DemoAccountSession(accountID:saved.user.id,method:saved.user.guest ? .testGuest : .password)
        }
    }

    func authenticate(action:String,username:String = "",password:String = "",name:String = "") async {
        guard !isBusy else { return };isBusy = true;error = nil
        defer { isBusy = false }
        do {
            let remote = try await PlatformAPI.shared.authenticate(action,username:username.trimmingCharacters(in:.whitespacesAndNewlines),
                password:password,name:name.trimmingCharacters(in:.whitespacesAndNewlines),upgrading:cloudSession)
            if !isolatedTest { try PlatformCredentials.write(remote) }
            cloudSession = remote;PlatformAPI.shared.activeSession = remote
            needsReauthentication = false
            cloudShouldImportLocal = action != "login"
            session = DemoAccountSession(accountID:remote.user.id,method:remote.user.guest ? .testGuest : .password)
            syncStatus = "正在连接账户资料"
            onSync?()
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult func signIn(_ method:LoginMethod, identifier:String = "", code:String = "") -> Bool {
        guard cloudSession == nil else { return false }
        guard isolatedTest || !PlatformAPI.shared.requiresAccountSession else {
            error = "请登录或注册星夜账户。"; return false
        }
        error = nil
        if method != .wechat {
            let clean = identifier.trimmingCharacters(in:.whitespacesAndNewlines)
            let matches = method == .email ? clean.lowercased() == DemoAccount.email : clean == DemoAccount.phone
            guard matches else {
                error = "当前仅支持预填的测试账号，点“恢复测试信息”即可继续。"; return false
            }
            guard code.trimmingCharacters(in:.whitespacesAndNewlines) == DemoAccount.code else {
                error = "测试验证码为123456，也可以点“获取验证码”自动填入。"; return false
            }
        }
        let next = DemoAccountSession(accountID:DemoAccount.id,method:method)
        guard let data = try? JSONEncoder().encode(next) else {
            error = "登录状态未能保存，请再试一次。"; return false
        }
        defaults.set(data,forKey:sessionKey)
        session = next
        return true
    }
    func switchDemoIdentity() {
        guard cloudSession == nil, isolatedTest || !PlatformAPI.shared.requiresAccountSession else { return }
        let next = DemoAccountSession(accountID:session?.accountID == DemoAccount.id ? DemoAccount.alternateID : DemoAccount.id,method:.wechat)
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data,forKey:sessionKey); session = next; error = nil
    }
    func signOut() {
        if let remote = cloudSession {
            do { if !isolatedTest { try PlatformCredentials.write(nil) } }
            catch { self.error = error.localizedDescription;return }
            Task { _ = try? await PlatformAPI.shared.request("POST","/v1/auth/logout",token:remote.token) }
            cloudSession = nil;PlatformAPI.shared.activeSession = nil;syncStatus = "本机保存"
            needsReauthentication = false;hasSyncConflicts = false
        }
        defaults.removeObject(forKey:sessionKey)
        session = nil; error = nil
        // Character settings, memories and conversation files belong to the same demo identity.
        // Logging out only ends the local session; it does not delete or migrate those files.
    }
}
