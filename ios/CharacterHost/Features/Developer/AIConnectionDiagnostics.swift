#if STARRY_TEST_TOOLS
import SwiftUI

/// Read-only on-device evidence. Never invokes a model or writes credentials to
/// the report. The launch flag is available only in development installations.
struct AIConnectionDiagnostics: View {
    @State private var status="Checking AI connection…"
    var body: some View {
        ScrollView {Text(verbatim:status).font(.system(size:13,design:.monospaced)).textSelection(.enabled).padding(24)}
            .background(Theme.background).foregroundStyle(Theme.ink).task {await run()}
    }
    private func run() async {
        var results:[[String:String]]=[]
        let api=CharacterAI(accountID:"guest",characterID:ModelDescriptor.all.first!.id)
        if let request=try? api.request("/v1/status",paid:false) {
            results.append(await probe(request,label:"authenticated-status"))
            if let base=request.url,let url=URL(string:"/health",relativeTo:base)?.absoluteURL {
                results.append(await probe(URLRequest(url:url),label:"bonjour-health"))
            }
        }
        let args=ProcessInfo.processInfo.arguments
        if let index=args.firstIndex(of:"--ai-probe-url"),index+1<args.count,
           let url=URL(string:args[index+1]+"/health"),["http","https"].contains(url.scheme ?? "") {
            results.append(await probe(URLRequest(url:url),label:"diagnostic-alternative"))
        }
        let report:[String:Any] = ["timestamp":ISO8601DateFormatter().string(from:Date()),"paidCalls":0,"results":results]
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("ai-connection-diagnostic.json")
            try? data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            status=String(decoding:data,as:UTF8.self)
        }
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
