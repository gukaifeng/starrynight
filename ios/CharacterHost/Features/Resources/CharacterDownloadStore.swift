import Foundation
import CryptoKit
import ZIPFoundation
import os

private final class CharacterDownloadGuard:NSObject,URLSessionDownloadDelegate,Sendable {
    let expectedSize:Int64
    let progress:@Sendable (Int64)->Void
    private let lastUpdate=OSAllocatedUnfairLock(initialState:0.0)
    init(expectedSize:Int64,progress:@escaping @Sendable (Int64)->Void) {self.expectedSize=expectedSize;self.progress=progress}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?)->Void) {completionHandler(nil)}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>expectedSize || totalBytesExpectedToWrite>expectedSize {downloadTask.cancel()}
        else {
            let now=ProcessInfo.processInfo.systemUptime
            let report=lastUpdate.withLock {last in
                if now-last<0.10 && totalBytesWritten<expectedSize{return false}
                last=now;return true
            }
            if report{progress(totalBytesWritten)}
        }
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {}
}

/// Transport/cache layer only. A verified release is activated by the runtime adapter.
/// Credentials never enter the package; keys are derived from account + character.
actor CharacterDownloadStore {
    struct Manifest:Codable,Sendable,Equatable {
        var schemaVersion:Int
        var characterId:String
        var releaseId:String
        var version:Int64
        var platform:String
        var runtimeVersion:String
        var files:[File]
    }
    struct File:Codable,Sendable,Equatable {
        var path:String
        var size:Int64
        var sha256:String
        var url:String?
        var headers:[String:String]?
    }
    struct Package:Codable,Sendable {
        let schemaVersion:Int
        let characterID,platform,runtimeVersion,bundle:String
        let version:Int64
        let bundleCRC:UInt32
        let files:[Member]
    }
    struct Member:Codable,Sendable {let path,sha256:String;let size:Int64}
    enum Failure:LocalizedError {
        case invalidManifest,invalidResponse,integrity,insufficientSpace,insecureURL,inUse
        var errorDescription:String? {
            switch self {
            case .invalidManifest:"角色资源清单不兼容或不完整。"
            case .invalidResponse:"角色下载暂时不可用，请稍后再试。"
            case .integrity:"角色资源校验失败，原有版本已保留。"
            case .insufficientSpace:"空间不足，请先清理缓存再下载。"
            case .insecureURL:"角色下载地址未通过安全检查。"
            case .inUse:"角色资源正在使用，请稍后再试。"
            }
        }
    }
    static let shared=CharacterDownloadStore()
    private let root:URL
    private let transport:URLSession
    private var inFlight=Set<String>()
    init(root:URL?=nil,transport:URLSession?=nil) {
        self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CharacterDownloads",isDirectory:true)
        let cfg=URLSessionConfiguration.ephemeral;cfg.timeoutIntervalForRequest=60;cfg.timeoutIntervalForResource=3600
        self.transport=transport ?? URLSession(configuration:cfg)
    }
    nonisolated static func safeRelativePath(_ value:String)->Bool {
        !value.isEmpty && value.count<=240 && value.unicodeScalars.allSatisfy({CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-").contains($0)}) && !value.hasPrefix("/") && !value.contains("\\") &&
        value.split(separator:"/",omittingEmptySubsequences:false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    struct Usage:Sendable,Identifiable {let id:String;let bytes:Int64;let installed:Bool;let downloading:Bool}
    private func directory(_ id:String,accountID:String,platform:String)->URL {
        let key=SHA256.hash(data:Data((accountID+"|"+id+"|"+platform).utf8)).map{String(format:"%02x",$0)}.joined()
        return root.appendingPathComponent(key,isDirectory:true)
    }
    func usage(characterIDs:Set<String>,accountID:String,platform:String)throws->[Usage] {
        guard !accountID.isEmpty,["ios","ios-simulator"].contains(platform) else {throw Failure.invalidManifest}
        return try characterIDs.sorted().map {id in
            let base=directory(id,accountID:accountID,platform:platform)
            var bytes:Int64=0
            if FileManager.default.fileExists(atPath:base.path) {
                let keys:Set<URLResourceKey>=[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]
                var failure:Error?
                let files=FileManager.default.enumerator(at:base,includingPropertiesForKeys:Array(keys),options:[],errorHandler:{_,error in failure=error;return false})
                while let file=files?.nextObject() as? URL {
                    let values=try file.resourceValues(forKeys:keys)
                    if values.isSymbolicLink==true {files?.skipDescendants();continue}
                    if values.isRegularFile==true {bytes+=Int64(values.fileSize ?? 0)}
                }
                if let failure{throw failure}
            }
            return Usage(id:id,bytes:bytes,installed:try installed(characterID:id,accountID:accountID,platform:platform) != nil,
                         downloading:inFlight.contains(base.lastPathComponent))
        }
    }
    /// Account-scoped, including older releases and interrupted partials. Rename
    /// first so a concurrent restore never sees half a package. Never touch chats.
    func remove(characterID:String,accountID:String,platform:String)throws {
        guard !characterID.isEmpty,!accountID.isEmpty,["ios","ios-simulator"].contains(platform) else {throw Failure.invalidManifest}
        let base=directory(characterID,accountID:accountID,platform:platform)
        guard !inFlight.contains(base.lastPathComponent) else {throw Failure.inUse}
        guard FileManager.default.fileExists(atPath:base.path) else {return}
        let values=try base.resourceValues(forKeys:[.isSymbolicLinkKey]);guard values.isSymbolicLink != true else {throw Failure.integrity}
        let trash=root.appendingPathComponent("removed-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.moveItem(at:base,to:trash)
        do {try FileManager.default.removeItem(at:trash)}
        catch {try? FileManager.default.moveItem(at:trash,to:base);throw error}
    }
    func install(_ manifest:Manifest,accountID:String,progress:@escaping @Sendable (Double,String)->Void = {_,_ in}) async throws -> URL {
        guard manifest.schemaVersion==1,manifest.version>0,!manifest.characterId.isEmpty,!manifest.releaseId.isEmpty,["xcp/1","starry-runtime/1"].contains(manifest.runtimeVersion),
              ["ios","ios-simulator"].contains(manifest.platform),manifest.files.count>0,manifest.files.count<=64,
              Set(manifest.files.map(\.path)).count==manifest.files.count,
              manifest.files.allSatisfy({Self.safeRelativePath($0.path) && $0.path != "manifest.json" && $0.size>0 && $0.size<=8*1024*1024*1024 && $0.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}) else {throw Failure.invalidManifest}
        let key=SHA256.hash(data:Data((accountID+"|"+manifest.characterId+"|"+manifest.platform).utf8)).map{String(format:"%02x",$0)}.joined()
        guard !accountID.isEmpty,!inFlight.contains(key) else {throw Failure.invalidResponse}
        inFlight.insert(key);defer {inFlight.remove(key)}
        let base=root.appendingPathComponent(key,isDirectory:true)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        var protectedBase=base;var attributes=URLResourceValues();attributes.isExcludedFromBackup=true
        try protectedBase.setResourceValues(attributes)
#if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:base.path)
#endif
        let release=base.appendingPathComponent(String(manifest.version),isDirectory:true)
        let total=manifest.files.reduce(Int64(0)){$0+$1.size}
        guard total<=8*1024*1024*1024 else {throw Failure.invalidManifest}
        let free=(try? base.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        guard free>total+64*1024*1024 else {throw Failure.insufficientSpace}
        let staging=base.appendingPathComponent("partial-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:staging)}
        var completed:Int64=0
        for file in manifest.files {
            try Task.checkCancellation()
            guard let raw=file.url,let url=URL(string:raw),url.scheme=="https",url.user==nil,url.password==nil,url.host != nil else {throw Failure.insecureURL}
            var request=URLRequest(url:url)
            for (name,value) in file.headers ?? [:] {guard !["authorization","cookie","host"].contains(name.lowercased()),!value.contains("\r"),!value.contains("\n") else {throw Failure.invalidManifest};request.setValue(value,forHTTPHeaderField:name)}
            let baseline=completed
            let (temp,response)=try await transport.download(for:request,delegate:CharacterDownloadGuard(expectedSize:file.size,progress:{ bytes in progress(Double(baseline+bytes)/Double(total),"正在下载") }))
            defer {try? FileManager.default.removeItem(at:temp)}
            guard let http=response as? HTTPURLResponse,http.statusCode==200 else {throw Failure.invalidResponse}
            guard (try temp.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init)==file.size else {throw Failure.integrity}
            let handle=try FileHandle(forReadingFrom:temp);defer {try? handle.close()}
            var hash=SHA256()
            while let bytes=try handle.read(upToCount:1024*1024),!bytes.isEmpty {hash.update(data:bytes);try Task.checkCancellation()}
            let digest=hash.finalize().map{String(format:"%02x",$0)}.joined()
            guard digest==file.sha256 else {throw Failure.integrity}
            let destination=staging.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try FileManager.default.moveItem(at:temp,to:destination)
            completed+=file.size
        }
        if manifest.runtimeVersion=="starry-runtime/1" {
            guard manifest.files.count==1,manifest.files[0].path=="character.zip" else {throw Failure.invalidManifest}
            progress(1,"正在校验与展开")
            try Self.expand(staging.appendingPathComponent("character.zip"),to:staging.appendingPathComponent("content"),manifest:manifest)
            try FileManager.default.removeItem(at:staging.appendingPathComponent("character.zip"))
        }
        var durable=manifest;durable.files=manifest.files.map {var f=$0;f.url=nil;f.headers=nil;return f}
        try Task.checkCancellation()
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        try encoder.encode(durable).write(to:staging.appendingPathComponent("manifest.json"),options:.atomic)
        if FileManager.default.fileExists(atPath:release.path) {
            let old=try Data(contentsOf:release.appendingPathComponent("manifest.json"))
            guard try JSONDecoder().decode(Manifest.self,from:old) == durable else {throw Failure.integrity}
        } else {try FileManager.default.moveItem(at:staging,to:release)}
        try Data(String(manifest.version).utf8).write(to:base.appendingPathComponent("current"),options:.atomic)
        return release
    }
    private static func digest(_ url:URL)throws->String {
        let file=try FileHandle(forReadingFrom:url);defer {try? file.close()};var hash=SHA256()
        while let bytes=try file.read(upToCount:1024*1024),!bytes.isEmpty {try Task.checkCancellation();hash.update(data:bytes)}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func expand(_ source:URL,to destination:URL,manifest:Manifest)throws {
        let archive=try Archive(url:source,accessMode:.read)
        let entries=Array(archive)
        guard entries.count<=128,Set(entries.map(\.path)).count==entries.count,
              entries.allSatisfy({$0.type == .file && safeRelativePath($0.path) && $0.uncompressedSize<=2*1024*1024*1024}),
              let header=archive["package.json"],header.uncompressedSize<128*1024 else {throw Failure.invalidManifest}
        var data=Data();_ = try archive.extract(header){data.append($0)}
        let package=try JSONDecoder().decode(Package.self,from:data)
        guard package.schemaVersion==1,package.characterID==manifest.characterId,package.version==manifest.version,
              package.platform==manifest.platform,package.runtimeVersion==manifest.runtimeVersion,
              package.bundle=="runtime/character.bundle",package.files.count>0,
              Set(package.files.map(\.path)).count==package.files.count,
              Set(entries.map(\.path))==Set(package.files.map(\.path)).union(["package.json"]),
              package.files.allSatisfy({safeRelativePath($0.path) && $0.path != "package.json" && $0.size>0 && $0.size<=2*1024*1024*1024 && $0.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}),
              package.files.contains(where:{$0.path==package.bundle}) else {throw Failure.invalidManifest}
        let total=package.files.reduce(Int64(0)){$0+$1.size}
        let free=(try? source.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        guard total<=4*1024*1024*1024,free>total+64*1024*1024 else {throw Failure.insufficientSpace}
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        for member in package.files {
            try Task.checkCancellation()
            guard let entry=archive[member.path],Int64(entry.uncompressedSize)==member.size else {throw Failure.integrity}
            let output=destination.appendingPathComponent(member.path)
            try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
            _ = try archive.extract(entry,to:output)
            guard try digest(output)==member.sha256 else {throw Failure.integrity}
        }
        try data.write(to:destination.appendingPathComponent("package.json"),options:.atomic)
    }
    func installed(characterID:String,accountID:String,platform:String)throws->URL? {
        let key=SHA256.hash(data:Data((accountID+"|"+characterID+"|"+platform).utf8)).map{String(format:"%02x",$0)}.joined()
        let base=root.appendingPathComponent(key)
        guard let version=try? String(contentsOf:base.appendingPathComponent("current"),encoding:.utf8),Int64(version) != nil else {return nil}
        let release=base.appendingPathComponent(version)
        guard let data=try? Data(contentsOf:release.appendingPathComponent("content/package.json")),
              let package=try? JSONDecoder().decode(Package.self,from:data),package.characterID==characterID,
              package.runtimeVersion=="starry-runtime/1",package.platform==platform,
              FileManager.default.fileExists(atPath:release.appendingPathComponent("content/"+package.bundle).path) else {return nil}
        return release
    }
}
