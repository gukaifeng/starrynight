import Foundation

@main struct AccountCoreTests {
    @MainActor static func main() throws {
        let name = "xiaoban-account-tests-"+UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let key = "xiaoban.demo-account.v1"
        let account = AccountStore(defaults:defaults,arguments:[])
        precondition(!account.isSignedIn)
        for method in LoginMethod.allCases {
            precondition(account.signIn(method,identifier:method == .email ? DemoAccount.email : DemoAccount.phone,code:DemoAccount.code))
            precondition(account.session?.accountID == DemoAccount.id && account.session?.method == method)
            let restored = AccountStore(defaults:defaults,arguments:[])
            precondition(restored.session == account.session)
            // Only identity and method are persisted, never entered credentials or codes.
            let persisted = String(decoding:defaults.data(forKey:key)!,as:UTF8.self)
            precondition(!persisted.contains(DemoAccount.code) && !persisted.contains(DemoAccount.email) && !persisted.contains(DemoAccount.phone))
            account.signOut()
            precondition(!AccountStore(defaults:defaults,arguments:[]).isSignedIn)
        }
        precondition(!account.signIn(.email,identifier:"someone@example.com",code:DemoAccount.code))
        precondition(!account.signIn(.phone,identifier:DemoAccount.phone,code:""))
        precondition(!account.signIn(.email,identifier:DemoAccount.email,code:"111111"))
        precondition(!account.isSignedIn && account.error != nil)
        precondition(account.signIn(.email,identifier:"  HELLO@XIAOBAN.EXAMPLE\n",code:" 123456 "))
        precondition(account.error == nil)
        defaults.set(Data("not-json".utf8),forKey:key)
        precondition(!AccountStore(defaults:defaults,arguments:[]).isSignedIn)
        defaults.set(try JSONEncoder().encode(DemoAccountSession(accountID:"unknown",method:.wechat)),forKey:key)
        precondition(!AccountStore(defaults:defaults,arguments:[]).isSignedIn)
        print("PASS: three methods share one identity; session restore/logout; invalid input; no persisted credentials; damaged session rejected")
    }
}
