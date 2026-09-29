import Foundation
#if !os(iOS)
@main
#endif
struct CompanionExperienceTests {
    @MainActor static func main() throws { print(try run()) }
    @MainActor static func run() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-migration-\(UUID())/journal.json")
        defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        var old = CompanionArchive(); old.schemaVersion = 1
        var role = CharacterRecord(profile:CharacterProfile(name:"琪宝"))
        role.messages = [CompanionMessage(role:"user",text:"过去的测试"),CompanionMessage(role:"assistant",text:"过去的模拟回复")]
        role.memories = [CompanionMemory(text:"我喜欢下雨")]
        var experience = CompanionExperiences(); experience.preferences.nickname = "小北"; role.experiences = experience
        old.characters["anime-kipfel"] = role
        try CompanionPersistence.write(old,to:url)
        let store = CompanionStore(storageURL:url)
        precondition(store.archive.schemaVersion == 2)
        precondition(store.record("anime-kipfel").messages.isEmpty)
        precondition(store.record("anime-kipfel").memories.first?.text == "我喜欢下雨")
        precondition(store.record("anime-kipfel").together.preferences.nickname == "小北")
        precondition(FileManager.default.fileExists(atPath:url.appendingPathExtension("before-real-ai").path))
        store.update("anime-kipfel") { $0.messages.append(CompanionMessage(role:"assistant",text:"真实回复",source:"cloud-v1")) }
        let reopened = CompanionStore(storageURL:url)
        precondition(reopened.record("anime-kipfel").messages.count == 1)
        reopened.activateAccount("someone-else")
        precondition(reopened.record("anime-kipfel").messages.isEmpty)
        precondition(store.record("anime-mamehinata").memories.isEmpty)
        precondition(CompanionStory.all.count == 3)
        return "PASS: real-AI migration, backup, retained memories, account/role isolation and restart persistence"
    }
}
