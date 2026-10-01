import Foundation

@main struct PlatformSyncTests {
    @MainActor static func main() throws {
        let base=JSONValue.object(["music":.number(0.8),"theme":.string("silver"),"future":.object(["enabled":.bool(true)])])
        let local=JSONValue.object(["music":.number(0.2),"theme":.string("silver"),"future":.object(["enabled":.bool(true)])])
        let cloud=JSONValue.object(["music":.number(0.5),"theme":.string("silver")])
        precondition(AccountSyncMerge.decide(knownVersion:2,known:base,pending:local,remoteVersion:2,remote:base) == .keepLocal)
        precondition(AccountSyncMerge.decide(knownVersion:2,known:base,pending:local,remoteVersion:3,remote:cloud) == .conflict)
        precondition(AccountSyncMerge.decide(knownVersion:2,known:base,pending:nil,remoteVersion:3,remote:cloud) == .apply)
        precondition(AccountSyncMerge.decide(knownVersion:2,known:base,pending:local,remoteVersion:3,remote:local) == .apply)
        precondition(AccountSyncMerge.decide(knownVersion:2,known:base,pending:local,remoteVersion:1,remote:cloud) == .stale)
        precondition(AccountSyncMerge.decide(knownVersion:nil,known:nil,pending:local,remoteVersion:1,remote:base) == .keepLocal)
        precondition(AccountSyncMerge.decide(knownVersion:2,known:base,pending:local,remoteVersion:3,remote:.null) == .conflict)
        precondition(AccountSyncMerge.diff(old:base,new:local) == .object(["music":.number(0.2)]))
        precondition(AccountSyncMerge.diff(old:base,new:.object([:])).object?["future"] == .null)
        precondition(AccountSyncMerge.overlay(known:.object(["music":.number(0.2)]),on:base) == local)
        let encoded=try JSONEncoder().encode(base)
        let decoded=try JSONDecoder().decode(JSONValue.self,from:encoded)
        precondition(decoded == base)
        let api=PlatformAPI(baseURL:URL(string:"https://accounts.example.test"))
        precondition(api.requiresAuthentication(for:"fixture-user"))
        precondition(!PlatformAPI(baseURL:URL(string:"http://127.0.0.1:8090")).requiresAuthentication(for:"local-demo"))
        let user=PlatformUser(id:"fixture-user",username:"fixture",guest:false,version:1,profile:["display_name":.string("星夜伙伴")])
        api.activeSession=PlatformSession(token:"fixture-token",expiresAt:"2026-10-30T00:00:00Z",user:user)
        precondition(!api.requiresAuthentication(for:user.id))
        precondition(api.requiresAuthentication(for:"other-user"))
        let request=try api.aiRequest(accountID:user.id,path:"/v1/asr/anime-kipfel")
        precondition(request?.url?.absoluteString == "https://accounts.example.test/v1/ai/asr/anime-kipfel")
        precondition(request?.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token")
        let wrongAccount=try api.aiRequest(accountID:"other-user",path:"/v1/status")
        precondition(wrongAccount == nil)
        api.activeSession=nil
        precondition(api.requiresAuthentication(for:user.id))
        print("Platform sync: 19 checks passed (conflicts, offline edits, unknown fields, account-scoped AI request, cloud authentication gate; no network or paid calls).")
    }
}
