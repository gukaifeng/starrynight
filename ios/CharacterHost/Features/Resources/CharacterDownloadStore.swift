import Foundation
import CryptoKit

private final class CharacterDownloadGuard:NSObject,URLSessionDownloadDelegate,Sendable {
    let expectedSize:Int64
    init(expectedSize:Int64) {self.expectedSize=expectedSize}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?)->Void) {completionHandler(nil)}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>expectedSize || totalBytesExpectedToWrite>expectedSize {downloadTask.cancel()}
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
    enum Failure:LocalizedError {
        case invalidManifest,invalidResponse,integrity,insufficientSpace,insecureURL
        var errorDescription:String? {
            switch self {
            case .invalidManifest:"角色资源清单不兼容或不完整。"
            case .invalidResponse:"角色下载暂时不可用，请稍后再试。"
            case .integrity:"角色资源校验失败，原有版本已保留。"
            case .insufficientSpace:"空间不足，请先清理缓存再下载。"
            case .insecureURL:"角色下载地址未通过安全检查。"
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
    func install(_ manifest:Manifest,accountID:String) async throws -> URL {
        guard manifest.schemaVersion==1,manifest.version>0,!manifest.characterId.isEmpty,!manifest.releaseId.isEmpty,manifest.runtimeVersion=="xcp/1",
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
        for file in manifest.files {
            try Task.checkCancellation()
            guard let raw=file.url,let url=URL(string:raw),url.scheme=="https",url.user==nil,url.password==nil,url.host != nil else {throw Failure.insecureURL}
            var request=URLRequest(url:url)
            for (name,value) in file.headers ?? [:] {guard !["authorization","cookie","host"].contains(name.lowercased()),!value.contains("\r"),!value.contains("\n") else {throw Failure.invalidManifest};request.setValue(value,forHTTPHeaderField:name)}
            let (temp,response)=try await transport.download(for:request,delegate:CharacterDownloadGuard(expectedSize:file.size))
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
        }
        var durable=manifest;durable.files=manifest.files.map {var f=$0;f.url=nil;f.headers=nil;return f}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        try encoder.encode(durable).write(to:staging.appendingPathComponent("manifest.json"),options:.atomic)
        if FileManager.default.fileExists(atPath:release.path) {
            let old=try Data(contentsOf:release.appendingPathComponent("manifest.json"))
            guard try JSONDecoder().decode(Manifest.self,from:old) == durable else {throw Failure.integrity}
        } else {try FileManager.default.moveItem(at:staging,to:release)}
        try Data(String(manifest.version).utf8).write(to:base.appendingPathComponent("current"),options:.atomic)
        return release
    }
}
