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
        do { try CompanionPersistence.write(next,to:url); archive = next; error = nil; return true }
        catch { self.error = "游客记录暂时未能保存到账号，请检查存储空间。"; return false }
    }
    var chatDisplay = ChatDisplaySettings()
    @ObservationIgnored private let chatDisplayDefaults: UserDefaults
    @ObservationIgnored private var recoveryBlocked = false
    let url: URL
    let dialogue: any DialogueProviding
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
        let data = try! Data(contentsOf:Bundle.main.url(forResource:"LocalDialogue",withExtension:"json")!)
        dialogue = try! LocalDialogue(data:data)
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
        do { try CompanionPersistence.write(next,to:url); archive = next; error = nil }
        catch { self.error = "保存失败，改动尚未写入。请检查设备存储空间后重试。" }
    }
    func saveProfile(_ profile: CharacterProfile, id: String) {
        var clean = profile; clean.normalize(); update(id) { $0.profile = clean }
    }
    func saveChatDisplay() -> Bool {
        chatDisplay = chatDisplay.normalized
        chatDisplay.save(to:chatDisplayDefaults)
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
