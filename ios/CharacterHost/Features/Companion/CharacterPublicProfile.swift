import Foundation

struct CharacterPublicProfile: Codable, Sendable, Identifiable {
    let id,name,invitation,story,occupation,world,tone:String
    let traits,likes:[String]
    var dialogueLanguage:String? = nil
    var scenarios:[CompanionStory]? = nil
    var profileRevision:String? = nil
    var englishOnly:Bool {dialogueLanguage == "en"}
    func supersedes(_ bundled:Self?)->Bool {
        guard let revision=bundled?.profileRevision else {return true}
        return (profileRevision ?? "") >= revision
    }
    private struct Catalog:Decodable {let characters:[CharacterPublicProfile]}
    private static let catalog:[CharacterPublicProfile] = {
        guard let url=Bundle.main.url(forResource:"CharacterPublicProfiles",withExtension:"json"),
              let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Catalog.self,from:data) else{return []}
        return value.characters
    }()
    static func find(_ id:String)->Self? {catalog.first {$0.id==id}}
}

struct AIInspectionReport:Decodable,Sendable {
    struct Section:Decodable,Sendable,Identifiable {
        let id,title,detail,content:String
        var isEmpty:Bool { ["", "{}", "[]", "null"].contains(content.trimmingCharacters(in:.whitespacesAndNewlines)) }
    }
    let version:Int
    let characterId,capturedAt:String
    var sections:[Section]
    var fullText:String {
        "星夜 AI 设定检查 · \(characterId)\n\(capturedAt)\n\n"+sections.map {"【\($0.title)】\n\($0.detail)\n\($0.content)"}.joined(separator:"\n\n")
    }
}
