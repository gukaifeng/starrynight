import Foundation
import CryptoKit

/// Disposable, account/character/voice scoped cache. No conversation text in filenames.
/// The 64 MB disk budget uses last access (LRU); the OS can purge the Caches directory.
@MainActor final class SpeechClipCache {
    static let shared = SpeechClipCache()
    private let memory = NSCache<NSString,NSData>()
    private let directory: URL
    private(set) var generation = UUID()
    private var clearing = false
    init(directory: URL? = nil) {
        memory.totalCostLimit = 16*1024*1024
        self.directory = directory ?? CacheLocations.live.speech
        try? FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
    }
    func key(scope:String,text:String,speed:Double) -> String {
        // Refresh pre-sanitizer audio too: old clips may have spoken stage
        // directions. New playback uses the same voice and clean spoken text.
        SHA256.hash(data:Data((scope+"|qwen-audio-3.1-designed-v2-spoken-v2|"+String(speed)+"|"+text).utf8)).map { String(format:"%02x",$0) }.joined()
    }
    func data(_ key:String) -> Data? {
        let url = directory.appendingPathComponent(key+".wav")
        if let data = memory.object(forKey:key as NSString) {
            try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:url.path)
            return data as Data
        }
        guard let data = try? Data(contentsOf:url), data.count <= 8*1024*1024 else { return nil }
        memory.setObject(data as NSData,forKey:key as NSString,cost:data.count)
        try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:url.path)
        return data
    }
    func insert(_ data:Data,key:String) {
        insert(data,key:key,generation:generation)
    }
    func insert(_ data:Data,key:String,generation:UUID) {
        guard !clearing, generation == self.generation else { return }
        guard data.count <= 8*1024*1024 else { return }
        memory.setObject(data as NSData,forKey:key as NSString,cost:data.count)
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try? data.write(to:directory.appendingPathComponent(key+".wav"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        let files = (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey])) ?? []
        let entries = files.compactMap { url -> (URL,Int,Date)? in
            guard let values = try? url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]) else { return nil }
            return (url,values.fileSize ?? 0,values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0+$1.1 }
        for entry in entries where bytes > 64*1024*1024 { try? FileManager.default.removeItem(at:entry.0); bytes -= entry.1 }
    }
    func beginClearing() {
        clearing = true; generation = UUID(); memory.removeAllObjects()
    }
    func removeConversation(scope:String,messages:[CompanionMessage]) {
        generation=UUID() // Retire in-flight inserts before removing owned clips.
        for message in messages {
            guard let script=message.aiScript else {continue}
            for beat in script.beats {
                let value=key(scope:scope,text:script.messageId+"|"+beat.beatId,speed:1)
                memory.removeObject(forKey:value as NSString)
                try? FileManager.default.removeItem(at:directory.appendingPathComponent(value+".wav"))
            }
        }
    }
    func endClearing() {
        memory.removeAllObjects(); generation = UUID(); clearing = false
    }
}
