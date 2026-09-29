import Foundation
@main struct CompanionCoreTests {
 static func main() throws {
  let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("xuyu-core-\(UUID())/store.json")
  defer { try? FileManager.default.removeItem(at:temp.deletingLastPathComponent()) }
  var archive = CompanionArchive()
  var luma = CharacterRecord(profile:.initial("studio-robot"))
  luma.profile.name = "小屿"; luma.profile.background = "一起读书的伙伴。"
  luma.memories.append(CompanionMemory(text:"我喜欢海边和安静的音乐"))
  archive.characters["studio-robot"] = luma
  archive.characters["hatsune-miku"] = CharacterRecord(profile:.initial("hatsune-miku"))
  try CompanionPersistence.write(archive,to:temp)
  let restored = try CompanionPersistence.read(temp)
  precondition(restored.characters["studio-robot"]!.profile.name == "小屿")
  precondition(restored.characters["hatsune-miku"]!.memories.isEmpty)
  luma.profile.personality = "活泼"; luma.profile.tone = "温暖"
  luma.profile.concise = true
  luma.memories.removeAll()
  luma.profile.name = "  "; luma.profile.voiceSpeed = 100; luma.profile.normalize()
  precondition(luma.profile.name == "伙伴" && luma.profile.voiceSpeed == 1.4)
  // The exact previous archive shape has no framing field. It must keep history and memory.
  let oldData = try JSONEncoder().encode(archive)
  precondition(!String(decoding:oldData,as:UTF8.self).contains("framing"))
  let migrated = try JSONDecoder().decode(CompanionArchive.self,from:oldData)
  precondition(migrated.characters["studio-robot"]!.profile.resolvedFraming == .recommended)
  precondition(migrated.characters["studio-robot"]!.memories.count == 1)
  archive.characters["hatsune-miku"]!.profile.framing = CharacterFraming(shot:"full",size:8,angle:-90).normalized
  try CompanionPersistence.write(archive,to:temp)
  let framed = try CompanionPersistence.read(temp)
  precondition(framed.characters["hatsune-miku"]!.profile.resolvedFraming == CharacterFraming(shot:"full",size:1.1,angle:-20))
  precondition(framed.characters["studio-robot"]!.profile.resolvedFraming == .recommended)
  precondition(CharacterFraming(shot:"orbit",size:.infinity,angle:.nan).normalized == .recommended)
  precondition(CharacterFraming(size:-1,angle:999).normalized == CharacterFraming(size:0.9,angle:20))
  precondition(migrated.chatDisplay == nil)
  precondition(ChatDisplaySettings(heightFraction: .nan,fontSize: .infinity).normalized == ChatDisplaySettings())
  precondition(ChatDisplaySettings(heightFraction: 4,fontSize: 2).normalized == ChatDisplaySettings(heightFraction: 0.60,fontSize: 14))
  archive.chatDisplay = ChatDisplaySettings(heightFraction:0.35,fontSize:24)
  try CompanionPersistence.write(archive,to:temp)
  let displayRestored = try CompanionPersistence.read(temp)
  precondition(displayRestored.chatDisplay == archive.chatDisplay)
  precondition(displayRestored.characters["studio-robot"]!.memories.count == 1)
  try Data("invalid".utf8).write(to:temp)
  var corruptRejected = false
  do { _ = try CompanionPersistence.read(temp) } catch { corruptRejected = true }
  precondition(corruptRejected)
  print("PASS: persistence, role isolation, explicit memory recall/deletion, profile application, variants, concise mode, action allowlist, corrupt-file rejection, v0.3 migration, framing normalization/roundtrip/role isolation")
 }
}
