#if STARRY_TEST_TOOLS
import SwiftUI

/// On-device connection evidence. --account-probe creates and deletes its own
/// temporary account. Never invokes a model or writes credentials to the report.
/// These launch flags are available only in development installations.
struct AIConnectionDiagnostics: View {
    @State private var status="Checking AI connection…"
    var body: some View {
        ScrollView {Text(verbatim:status).font(.system(size:13,design:.monospaced)).textSelection(.enabled).padding(24)}
            .background(Theme.background).foregroundStyle(Theme.ink).task {await run()}
    }
    private func run() async {
        var results:[[String:String]]=[]
        let args=ProcessInfo.processInfo.arguments
        if let base=PlatformAPI.shared.baseURL,base.scheme == "https" {
            for path in ["/health/ready","/health/ai","/v1/capabilities","/v1/me"] {
                if let url=URL(string:path,relativeTo:base) {
                    results.append(await probe(URLRequest(url:url),label:"cloud"))
                }
            }
            if args.contains("--account-probe") {results += await accountProbe(base)}
        } else {
            let api=CharacterAI(accountID:"guest",characterID:ModelDescriptor.all.first!.id)
            if let request=try? api.request("/v1/status",paid:false) {
                results.append(await probe(request,label:"authenticated-status"))
                if let base=request.url,let url=URL(string:"/health",relativeTo:base)?.absoluteURL {
                    results.append(await probe(URLRequest(url:url),label:"bonjour-health"))
                }
            }
        }
        if let index=args.firstIndex(of:"--ai-probe-url"),index+1<args.count,
           let url=URL(string:args[index+1]+"/health"),["http","https"].contains(url.scheme ?? "") {
            results.append(await probe(URLRequest(url:url),label:"diagnostic-alternative"))
        }
        let report:[String:Any] = ["timestamp":ISO8601DateFormatter().string(from:Date()),"paidCalls":0,"results":results,
            "version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",
            "build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""]
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("ai-connection-diagnostic.json")
            try? data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            status=String(decoding:data,as:UTF8.self)
        }
    }
    @MainActor private func accountProbe(_ base:URL) async -> [[String:String]] {
        let api=PlatformAPI(baseURL:base)
        let username="probe_"+UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(16)
        let password=UUID().uuidString+UUID().uuidString
        var session:PlatformSession?
        var results:[[String:String]]=[]
        do {
            let registered=try await api.authenticate("register",username:username,password:password,name:"Connection check",upgrading:nil)
            session=registered
            results.append(["probe":"registration","status":"passed"])
            let loggedIn=try await api.authenticate("login",username:username,password:password,name:"",upgrading:nil)
            guard loggedIn.user.id==registered.user.id else {throw PlatformError.invalidResponse}
            api.activeSession=loggedIn
            let me=try await api.request("GET","/v1/me",token:loggedIn.token)
            guard me.object?["id"]?.string==registered.user.id else {throw PlatformError.invalidResponse}
            results.append(["probe":"login-and-identity","status":"passed"])
            guard let request=try api.aiRequest(accountID:loggedIn.user.id,path:"/v1/status") else {throw PlatformError.invalidResponse}
            results.append(await probe(request,label:"authenticated-ai-status"))
        } catch {
            results.append(["probe":"account-flow","status":"failed","description":error.localizedDescription])
        }
        if let session {
            do {
                _ = try await api.request("DELETE","/v1/me",token:session.token,
                    body:.object(["password":.string(password),"confirmation":.string("DELETE")]))
                results.append(["probe":"temporary-account-cleanup","status":"passed"])
                do {
                    _ = try await api.request("GET","/v1/me",token:session.token)
                    results.append(["probe":"revoked-session","status":"failed"])
                } catch PlatformError.status(401) {
                    results.append(["probe":"revoked-session","status":"passed"])
                }
            } catch {results.append(["probe":"cleanup-or-revocation","status":"failed","description":error.localizedDescription])}
        }
        return results
    }
    private func probe(_ original:URLRequest,label:String) async -> [String:String] {
        var request=original;request.timeoutInterval=6
        var result=["probe":label,"host":request.url?.host ?? "","path":request.url?.path ?? ""]
        let start=Date()
        do {
            let (data,response)=try await URLSession.shared.data(for:request)
            result["httpStatus"]=String((response as? HTTPURLResponse)?.statusCode ?? 0)
            if let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] {
                if let ready=json["ready"] as? Bool {result["providerReady"]=String(ready)}
                if let voices=json["voices"] as? [String:Bool] {
                    result["voiceCount"]=String(voices.count)
                    result["allVoicesReady"]=String(!voices.isEmpty && voices.values.allSatisfy {$0})
                }
                if let status=json["status"] as? String {result["status"]=status}
            }
        } catch {
            let value=error as NSError;result["error"]=value.domain+":"+String(value.code)
            result["description"]=value.localizedDescription
        }
        result["elapsedMs"]=String(Int(Date().timeIntervalSince(start)*1000));return result
    }
}
#endif
