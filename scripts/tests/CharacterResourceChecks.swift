import Foundation
import CryptoKit

/// Isolated, real file-system checks; never touches an installed user package.
enum CharacterResourceChecks {
    struct Failure:Error {let reason:String}
    static func run() async throws->String {
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("role-resources-"+UUID().uuidString)
        defer {try? fm.removeItem(at:root)}
        let store=CharacterDownloadStore(root:root.appendingPathComponent("downloads"))
        var count=0
        func check(_ value:Bool,_ reason:String)throws {count+=1;if !value{throw Failure(reason:reason)}}
        func folder(_ id:String,_ owner:String,_ platform:String)->URL {
            let key=SHA256.hash(data:Data((owner+"|"+id+"|"+platform).utf8)).map{String(format:"%02x",$0)}.joined()
            return root.appendingPathComponent("downloads/"+key)
        }
        func write(_ path:URL,_ bytes:Data)throws {try fm.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true);try bytes.write(to:path)}
        func release(_ id:String,_ owner:String,_ platform:String)throws {
            let base=folder(id,owner,platform), data=Data(repeating:0x7a,count:4096)
            let header:[String:Any]=["schemaVersion":1,"characterID":id,"platform":platform,"runtimeVersion":"starry-runtime/1","bundle":"runtime/character.bundle","version":2,"bundleCRC":0,"files":[]]
            try write(base.appendingPathComponent("2/content/package.json"),JSONSerialization.data(withJSONObject:header))
            try write(base.appendingPathComponent("2/content/runtime/character.bundle"),data)
            try write(base.appendingPathComponent("current"),Data("2".utf8))
            try write(base.appendingPathComponent("1/old.bundle"),data)
            try write(base.appendingPathComponent("partial-test/partial.bundle"),data)
        }
        let chat=root.appendingPathComponent("companion.json");try write(chat,Data("chat-memory-subscriptions".utf8))
        let original=try Data(contentsOf:chat)
        try release("role-a","alice","ios");try release("role-b","alice","ios")
        try release("role-a","bob","ios");try release("role-a","alice","ios-simulator")
        let first=try await store.usage(characterIDs:["role-a","role-b","missing"],accountID:"alice",platform:"ios")
        try check(first.count==3,"all known roles scanned")
        try check(first.first {$0.id=="missing"}?.bytes==0,"missing directory is empty")
        try check(first.first {$0.id=="role-a"}?.installed==true,"valid current release installed")
        try check((first.first {$0.id=="role-a"}?.bytes ?? 0)>12288,"counts older releases and partials")
        try await store.remove(characterID:"role-a",accountID:"alice",platform:"ios")
        let remaining=try await store.usage(characterIDs:["role-a","role-b"],accountID:"alice",platform:"ios")
        try check(remaining.first {$0.id=="role-a"}?.bytes==0,"whole chosen role removed")
        try check(remaining.first {$0.id=="role-b"}?.installed==true,"other role retained")
        let removed=try await store.installed(characterID:"role-a",accountID:"alice",platform:"ios")
        try check(removed==nil,"installed pointer cleared")
        let otherOwner=try await store.installed(characterID:"role-a",accountID:"bob",platform:"ios")
        let otherPlatform=try await store.installed(characterID:"role-a",accountID:"alice",platform:"ios-simulator")
        try check(otherOwner != nil,"other account retained");try check(otherPlatform != nil,"other platform retained")
        try check(try Data(contentsOf:chat)==original,"chats memories and subscriptions byte-identical")
        try await store.remove(characterID:"role-a",accountID:"alice",platform:"ios")
        try release("role-a","alice","ios")
        let reinstalled=try await store.installed(characterID:"role-a",accountID:"alice",platform:"ios")
        try check(reinstalled != nil,"same role can be installed again")
        let target=folder("symlink","alice","ios");try fm.createSymbolicLink(at:target,withDestinationURL:chat.deletingLastPathComponent())
        do {try await store.remove(characterID:"symlink",accountID:"alice",platform:"ios");throw Failure(reason:"symlink deleted")}catch CharacterDownloadStore.Failure.integrity {count+=1}
        try check(try Data(contentsOf:chat)==original,"symlink cannot delete outside download scope")
        do {try await store.remove(characterID:"role-b",accountID:"",platform:"ios");throw Failure(reason:"empty account accepted")}catch CharacterDownloadStore.Failure.invalidManifest {count+=1}
        return "PASS: \(count) character resource storage checks"
    }
}
