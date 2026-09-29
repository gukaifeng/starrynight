import Foundation
import UIKit

enum CacheStorageTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    @MainActor static func run() async throws -> String {
        var checks = 0
        func check(_ condition: Bool,_ message:String) throws {
            checks += 1; if !condition { throw Failure(description:message) }
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cache-core-"+UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let paths = CacheLocations.fixture(root), storage = CacheStorage(locations:paths)
        func write(_ url:URL,_ data:Data = Data(repeating:0x61,count:8193)) throws {
            try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url)
        }
        let empty = await storage.snapshot()
        try check(empty.bytes == 0 && empty.issues == 0 && empty.categories.count == 3,"missing roots are an empty cache")
        let chat = root.appendingPathComponent("Application Support/companion.json")
        let account = root.appendingPathComponent("Documents/account.json")
        try write(chat,Data("private chat and memories".utf8)); try write(account,Data("account and subscriptions".utf8))
        let originalChat = try Data(contentsOf:chat), originalAccount = try Data(contentsOf:account)
        let wave = paths.speech.appendingPathComponent(String(repeating:"a",count:64)+".wav")
        let portrait = paths.portraits.appendingPathComponent("hatsune-miku.png")
        let metadata = paths.portraits.appendingPathComponent("hatsune-miku.json")
        let export = paths.exports.appendingPathComponent(UUID().uuidString)
        let image = export.appendingPathComponent("星夜-对话-01.png")
        try write(wave); try write(portrait); try write(metadata); try write(image)
        let unknown = export.appendingPathComponent("do-not-touch.txt"); try write(unknown)
        let extra = paths.speech.appendingPathComponent("not-our-cache.wav"); try write(extra)
        try fm.createSymbolicLink(at:paths.portraits.appendingPathComponent("linked.png"),withDestinationURL:chat)
        let directoryLink = paths.exports.appendingPathComponent(UUID().uuidString)
        try fm.createSymbolicLink(at:directoryLink,withDestinationURL:chat.deletingLastPathComponent())
        let scanned = await storage.snapshot()
        try check(scanned.categories.reduce(0){$0+$1.files} == 4,"only allowed regular cache files counted")
        try check(scanned.bytes > 0 && scanned.issues == 0,"allocated size is measured")
        try check(scanned.removableFiles(in:[.speech]) == 1,"category selection")
        let first = await storage.clear([.speech])
        try check(first.removedFiles == 1 && first.removedBytes > 0 && first.failures == 0,"selected cache cleared")
        try check(!fm.fileExists(atPath:wave.path) && fm.fileExists(atPath:portrait.path) && fm.fileExists(atPath:image.path),"other categories preserved")
        try check(try Data(contentsOf:chat) == originalChat && Data(contentsOf:account) == originalAccount,"persistent data untouched")
        try check(fm.fileExists(atPath:extra.path) && fm.fileExists(atPath:unknown.path),"unknown files retained")
        let again = await storage.clear([.speech])
        try check(again.removedFiles == 0 && again.failures == 0,"idempotent clear")
        var lease: CacheFileLease? = try await storage.leaseExport(export)
        let protected = await storage.clear([.exports])
        try check(protected.removedFiles == 0 && protected.snapshot.protectedBytes > 0,"active rendering/preview/share is protected")
        await storage.release(lease!.id); lease = nil
        let now = Date()
        try await storage.retainSharedExport(export,now:now)
        let restarted = CacheStorage(locations:paths)
        let retained = await restarted.clear([.exports],now:now.addingTimeInterval(200))
        try check(retained.removedFiles == 0 && fm.fileExists(atPath:image.path),"24h share retention survives restart")
        let expired = await restarted.clear([.exports],now:now.addingTimeInterval(86_401))
        try check(expired.removedFiles == 2 && !fm.fileExists(atPath:image.path),"expired share image and marker removable")
        try check(fm.fileExists(atPath:unknown.path),"empty directory cleanup does not remove unknown files")
        try write(image)
        try await storage.retainSharedExport(export)
        await storage.cancelShareRetention(export)
        let cancelledShare = await storage.clear([.exports])
        try check(cancelledShare.removedFiles == 1,"cancelled share does not retain files for 24h")
        try write(image); try write(export.appendingPathComponent(CacheStorage.shareMarker),Data("broken".utf8))
        let corrupt = await storage.clear([.exports])
        try check(corrupt.removedFiles == 0 && corrupt.snapshot.protectedBytes > 0 && corrupt.snapshot.issues > 0,"invalid retention metadata is visible and conservative")
        await storage.cancelShareRetention(export)
        let none = await storage.clear([])
        try check(none.removedFiles == 0,"empty selection does not delete")
        let all = await storage.clear(Set(CacheCategory.allCases))
        try check(all.removedFiles == 3 && all.snapshot.bytes == 0,"clear all owned data")
        try check(try Data(contentsOf:chat) == originalChat && Data(contentsOf:account) == originalAccount,"all-cache clear preserves data and symlink targets")
        let linkedPaths = CacheLocations(speech:paths.portraits.appendingPathComponent("escape"),portraits:root.appendingPathComponent("absent"),exports:root.appendingPathComponent("absent-exports"))
        try fm.createSymbolicLink(at:linkedPaths.speech,withDestinationURL:chat.deletingLastPathComponent())
        let blocked = await CacheStorage(locations:linkedPaths).clear(Set(CacheCategory.allCases))
        try check(blocked.failures > 0 && blocked.removedFiles == 0,"symlink root rejected")

        let cache = SpeechClipCache(directory:paths.speech)
        let key = cache.key(scope:"a/miku",text:"你好",speed:1)
        let bytes = Data(repeating:0x61,count:400)
        cache.insert(bytes,key:key)
        try check(cache.data(key) == bytes,"speech cache usable before cleanup")
        let oldGeneration = cache.generation
        cache.beginClearing(); _ = await storage.clear([.speech])
        cache.insert(bytes,key:key,generation:oldGeneration)
        try check(cache.data(key) == nil,"old synthesis cannot restore cleared cache")
        let duringGeneration = cache.generation
        cache.endClearing(); cache.insert(bytes,key:key,generation:duringGeneration)
        try check(cache.data(key) == nil,"synthesis started during clear cannot repopulate after completion")
        cache.insert(bytes,key:key)
        try check(cache.data(key) == bytes,"new speech is cached normally")
        let portraits = CharacterPortraitStore(directory:paths.portraits)
        let model = ModelDescriptor.miku, profile = model.collection.initialProfile()
        let portraitKey = CharacterPortraitStore.key(model:model,profile:profile)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let png = UIGraphicsImageRenderer(size:CGSize(width:512,height:512),format:format).pngData { c in
            UIColor.cyan.setFill(); c.fill(CGRect(x:0,y:0,width:512,height:512))
        }
        try write(paths.portraits.appendingPathComponent(portraitKey+".png"),png)
        try check(portraits.accept(model:model,key:portraitKey) && portraits.hasCurrent(model,profile:profile),"portrait loaded")
        portraits.beginClearing(); _ = await storage.clear([.portraits]); portraits.endClearing()
        try check(portraits.image(model,profile:profile) == nil,"portrait memory invalidated with disk")
        try write(paths.portraits.appendingPathComponent(portraitKey+".png"),png)
        try check(portraits.accept(model:model,key:portraitKey) && portraits.image(model,profile:profile) != nil,"portrait regenerates from saved appearance")
        try check(try Data(contentsOf:chat) == originalChat && Data(contentsOf:account) == originalAccount,"regeneration does not alter persistent data")
        return "PASS: \(checks) cache checks · measured sizes, selection, leases, share retention, links, persistence, memory invalidation, regeneration"
    }
    static func prepareUIFixture() throws {
        let fm = FileManager.default, paths = CacheLocations.current
        let parent = paths.speech.deletingLastPathComponent()
        guard parent.lastPathComponent == "CacheReview" else { throw Failure(description:"fixture must be isolated") }
        try? fm.removeItem(at:parent)
        for category in CacheCategory.allCases { try fm.createDirectory(at:paths.directory(category),withIntermediateDirectories:true) }
        try Data((0..<256_000).map { UInt8($0 % 251) }).write(to:paths.speech.appendingPathComponent(String(repeating:"f",count:64)+".wav"))
        try Data((0..<128_000).map { UInt8($0 % 241) }).write(to:paths.portraits.appendingPathComponent("demo.png"))
        try Data("avatar metadata".utf8).write(to:paths.portraits.appendingPathComponent("demo.json"))
        for protected in [false,true] {
            let directory = paths.exports.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at:directory,withIntermediateDirectories:true)
            try Data((0..<640_000).map { UInt8($0 % 239) }).write(to:directory.appendingPathComponent("星夜-对话-01.png"))
            if protected { try Data(String(Date().addingTimeInterval(3600).timeIntervalSince1970).utf8).write(to:directory.appendingPathComponent(CacheStorage.shareMarker)) }
        }
    }
}
