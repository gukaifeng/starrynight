import Foundation

/// Authored, versioned first meetings. No provider call or audio-cache dependency.
/// A copied/user-created role inherits the opening of its runtime model.
struct CharacterOpening: Decodable, Sendable {
    let id:String
    let text:String
    let audio:String
    let language:String
    let visuals:[AIVisual]
    let audioReady:Bool
    let duration:Double?
    let parts:[AIReplyPart]?
    let readingDuration:Double?

    func script(characterID:String,messageID:UUID = UUID()) -> AIScript {
        AIScript(messageId:messageID.uuidString,characterId:characterID,text:text,
                 beats:[AIBeat(beatId:"opening",dialogue:AIDialogue(text:text),narrations:[],
                               visuals:visuals,duration:duration,parts:parts ?? [AIReplyPart(kind:"dialogue",text:text,at:0)],readingDuration:readingDuration)],
                 openingID:id)
    }
    func pcm(bundle:Bundle = .main) async throws -> Data {
        guard audioReady,let url=bundle.url(forResource:audio,withExtension:"pcm") else {
            throw AIConnectionError.remote("BUNDLED_OPENING_AUDIO_MISSING")
        }
        return try await Task.detached(priority:.userInitiated) {
            let data=try Data(contentsOf:url,options:.mappedIfSafe)
            guard data.count > 48000,data.count.isMultiple(of:2) else {
                throw AIConnectionError.remote("BUNDLED_OPENING_AUDIO_INVALID")
            }
            return data
        }.value
    }
}

enum CharacterOpenings {
    struct Catalog:Decodable {let schemaVersion:Int;let characters:[Package]}
    struct Package:Decodable {let characterID:String;let variants:[CharacterOpening];let legacyVariants:[CharacterOpening]?}
    private static let packages:[Package] = {
        guard let url=Bundle.main.url(forResource:"CharacterOpenings",withExtension:"json"),
              let data=try? Data(contentsOf:url),let catalog=try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.schemaVersion==1 else {return []}
        return catalog.characters
    }()
    static func random(for runtimeID:String) -> CharacterOpening? {
        packages.first(where:{$0.characterID==runtimeID})?.variants.randomElement()
    }
    static func find(_ id:String) -> CharacterOpening? {
        packages.lazy.flatMap {$0.variants+($0.legacyVariants ?? [])}.first(where:{$0.id==id})
    }
}
