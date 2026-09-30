import Foundation
import Observation

@MainActor @Observable
final class CompanionStore {
    private(set) var archive: CompanionArchive
    var error: String?
    private(set) var accountID = DemoAccount.id
    func activateAccount(_ id:String) { accountID = id }
    private func key(_ id:String) -> String { accountID == DemoAccount.id ? id : accountID + ":" + id }
    var currentRecords: [String:CharacterRecord] {
        if accountID == DemoAccount.id { return archive.characters.filter { !$0.key.contains(":") } }
        let prefix = accountID + ":"
        return Dictionary(uniqueKeysWithValues:archive.characters.filter { $0.key.hasPrefix(prefix) }.map { (String($0.key.dropFirst(prefix.count)),$0.value) })
    }
    func contains(_ id:String) -> Bool { archive.characters[key(id)] != nil }
    var guestTurns: Int { max(0,archive.guestTurns ?? 0) }
    var guestLimitReached: Bool { guestTurns >= 5 }
    /// Only a genuinely new account can adopt the guest journal. Existing accounts
    /// keep their own follow state, including an explicitly empty one.
    @discardableResult func importGuest(into id:String) -> Bool {
        guard !recoveryBlocked, archive.guestImportedBy == nil else { return false }
        let records = archive.characters.filter { $0.key.hasPrefix("guest:") }
        guard !records.isEmpty else { return false }
        var next = archive
        for (key,record) in records {
            let role = String(key.dropFirst("guest:".count))
            let destination = id == DemoAccount.id ? role : id + ":" + role
            guard next.characters[destination] == nil else { continue }
            next.characters[destination] = record
        }
        next.guestImportedBy = id
        do { try CompanionPersistence.write(next,to:url); writeRevision += 1;archive = next; error = nil; return true }
        catch { self.error = "游客记录暂时未能保存到账号，请检查存储空间。"; return false }
    }
    var chatDisplay = ChatDisplaySettings()
    @ObservationIgnored private let chatDisplayDefaults: UserDefaults
    @ObservationIgnored private var recoveryBlocked = false
    @ObservationIgnored private var batching = false
    @ObservationIgnored private var writeRevision=0
    let url: URL
    init(storageURL:URL? = nil,displayDefaults:UserDefaults? = nil,arguments:[String] = ProcessInfo.processInfo.arguments) {
        let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        let testing = arguments.contains("--companion-testing")
        let testingDisplay = testing || arguments.contains("--ui-testing")
        if let displayDefaults { chatDisplayDefaults = displayDefaults }
        else if let storageURL {
            chatDisplayDefaults = UserDefaults(suiteName:ChatDisplaySettings.fixturePreferenceSuite(for:storageURL))!
        } else if testingDisplay {
            chatDisplayDefaults = UserDefaults(suiteName:"starry.chat-display.ui-tests")!
        } else { chatDisplayDefaults = .standard }
        if storageURL == nil && testingDisplay && !arguments.contains("--keep-companion-data") {
            chatDisplayDefaults.removeObject(forKey:ChatDisplaySettings.fontPreferenceKey)
        }
        url = storageURL ?? directory.appendingPathComponent(testing ? "companion-test.json" : "companion.json")
        if testing && !arguments.contains("--keep-companion-data") { try? FileManager.default.removeItem(at:url) }
        do { archive = try CompanionPersistence.read(url) }
        catch {
            archive = CompanionArchive()
            do {
                try FileManager.default.copyItem(at:url,to:url.appendingPathExtension("recovery-\(Int(Date().timeIntervalSince1970))"))
                self.error = "本地资料读取失败，原文件已保留为恢复副本。"
            } catch {
                recoveryBlocked = true
                self.error = "本地资料无法读取或备份，已停止写入以保留原文件。请检查存储空间并重启后重试。"
            }
        }
        if archive.schemaVersion < 2 {
            do {
                // Preserve the previous test journal once before removing fabricated replies.
                let backup = url.appendingPathExtension("before-real-ai")
                if FileManager.default.fileExists(atPath:url.path) && !FileManager.default.fileExists(atPath:backup.path) {
                    try FileManager.default.copyItem(at:url,to:backup)
                }
                var migrated = archive
                for key in migrated.characters.keys {
                    migrated.characters[key]?.messages.removeAll { $0.source != "cloud-v1" }
                    migrated.characters[key]?.greeting = nil
                    migrated.characters[key]?.experiences?.stories = [:]
                    migrated.characters[key]?.experiences?.activeStoryID = nil
                    migrated.characters[key]?.experiences?.moments.removeAll { $0.kind == "story" }
                    migrated.characters[key]?.experiences?.suggestions = []
                }
                migrated.schemaVersion = 2; migrated.guestTurns = 0
                try CompanionPersistence.write(migrated,to:url); archive = migrated
            } catch { recoveryBlocked = true; self.error = "旧测试记录尚未备份，暂缓升级以保留原资料。" }
        }
        chatDisplay = ChatDisplaySettings.load(from:chatDisplayDefaults)
    }
    func record(_ id: String) -> CharacterRecord { archive.characters[key(id)] ?? CharacterRecord(profile:.initial(id)) }
    func update(_ id: String, countGuestTurn:Bool = false, _ change: (inout CharacterRecord) -> Void) {
        guard !recoveryBlocked else {
            error = "原资料尚未成功备份，不能覆盖。请检查存储空间并重启后重试。"; return
        }
        var next = archive
        if countGuestTurn && accountID == "guest" {
            guard !guestLimitReached else { error = "五轮体验已结束，登录后继续聊。"; return }
            next.guestTurns = guestTurns + 1
        }
        var record = record(id); change(&record)
        record.messages = Array(record.messages.suffix(1000))
        next.characters[key(id)] = record
        if batching { archive = next; error = nil; return }
        // Publish in-memory state immediately; encoding a multi-role archive and
        // atomic disk I/O must not stall a message insertion or keyboard animation.
        // The serial writer preserves every snapshot's order. Reads/sync imports
        // use the same queue, so reopening can never overtake a pending write.
        archive=next;error=nil;writeRevision += 1
        let revision=writeRevision
        CompanionPersistence.enqueue(next,to:url) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,revision==self.writeRevision else {return}
                switch result {
                case .success: self.error=nil;NotificationCenter.default.post(name:.accountDataChanged,object:nil)
                case .failure: self.error="记录仍保留在本次会话，暂未存入设备。请检查存储空间。"
                }
            }
        }
    }
    /// One disk write per incoming sync page, with rollback on a storage error.
    func applyCloudBatch(_ updates:() throws -> Void) throws {
        guard !batching,!recoveryBlocked else { throw CocoaError(.fileWriteUnknown) }
        writeRevision += 1
        let previous=archive;batching=true;error=nil
        defer { batching=false }
        do {
            try updates()
            if error != nil { throw CocoaError(.fileWriteUnknown) }
            try CompanionPersistence.write(archive,to:url)
        } catch { archive=previous;self.error="云端资料暂未写入，本机原记录已保留。";throw error }
    }
    func saveProfile(_ profile: CharacterProfile, id: String) {
        var clean = profile; clean.normalize(); update(id) { $0.profile = clean }
    }
    func saveChatDisplay() -> Bool {
        chatDisplay = chatDisplay.normalized
        chatDisplay.save(to:chatDisplayDefaults)
        NotificationCenter.default.post(name:.accountDataChanged,object:nil)
        return true
    }
    func addMemory(_ text: String, id: String) {
        let clean = String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
        guard !clean.isEmpty, !record(id).memories.contains(where: { $0.text == clean }) else { return }
        update(id) { $0.memories.append(CompanionMemory(text:clean)) }
    }
    func export(_ id: String) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Jinban-\(id).json")
        try encoder.encode(record(id)).write(to:destination,options:.atomic)
        return destination
    }
}
