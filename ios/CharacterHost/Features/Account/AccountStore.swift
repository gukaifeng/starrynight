import Foundation
import Observation

@MainActor @Observable
final class AccountStore {
    private(set) var session: DemoAccountSession?
    var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sessionKey: String
    var isSignedIn: Bool { session != nil }

    init(defaults:UserDefaults = .standard, arguments:[String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
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
        if let data = defaults.data(forKey:key),
           let saved = try? JSONDecoder().decode(DemoAccountSession.self,from:data),[DemoAccount.id,DemoAccount.alternateID].contains(saved.accountID) {
            session = saved
        }
#if DEBUG
        if arguments.contains("--ui-testing") && !arguments.contains("--auth-testing") && session == nil {
            session = DemoAccountSession(accountID:DemoAccount.id,method:.wechat)
        }
#endif
    }

    @discardableResult func signIn(_ method:LoginMethod, identifier:String = "", code:String = "") -> Bool {
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
        let next = DemoAccountSession(accountID:session?.accountID == DemoAccount.id ? DemoAccount.alternateID : DemoAccount.id,method:.wechat)
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data,forKey:sessionKey); session = next; error = nil
    }
    func signOut() {
        defaults.removeObject(forKey:sessionKey)
        session = nil; error = nil
        // Character settings, memories and conversation files belong to the same demo identity.
        // Logging out only ends the local session; it does not delete or migrate those files.
    }
}
