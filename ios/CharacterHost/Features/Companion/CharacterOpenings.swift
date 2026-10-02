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
    struct Package:Decodable {let characterID:String;let variants:[CharacterOpening];let legacyVariants:[CharacterOpening]?;let initialReplies:[String]?}
    private static let packages:[Package] = {
        guard let url=Bundle.main.url(forResource:"CharacterOpenings",withExtension:"json"),
              let data=try? Data(contentsOf:url),let catalog=try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.schemaVersion==1 else {return []}
        return catalog.characters
    }()
    static func variants(for runtimeID:String) -> [CharacterOpening] {
        packages.first(where:{$0.characterID==runtimeID})?.variants ?? []
    }
    static func random(for runtimeID:String) -> CharacterOpening? {
        packages.first(where:{$0.characterID==runtimeID})?.variants.randomElement()
    }
    static func find(_ id:String) -> CharacterOpening? {
        packages.lazy.flatMap {$0.variants+($0.legacyVariants ?? [])}.first(where:{$0.id==id})
    }
    /// A first meeting is bundled, so its initial reply choices can also be
    /// shown immediately while the optional online ranking warms in parallel.
    static func initialReplies(for runtimeID:String,messageID:String) -> [AIQuickReply] {
        let texts:[String]
        if let authored=packages.first(where:{$0.characterID==runtimeID})?.initialReplies,authored.count==3 {
            texts=authored
        } else {
        switch runtimeID {
        case "anime-kipfel": texts=["想听听书屋里的故事。","你找到的那片叶子呢？","我想和你聊聊今天。"]
        case "anime-mamehinata": texts=["先说说面包房吧！","我们去找一个小冒险。","我想分享今天的开心事。"]
        case "anime-chiffon": texts=["陪我挑一束花吧。","你最喜欢什么季节？","我们聊聊今天的心情。"]
        case "anime-karin": texts=["画一张明信片给我吧。","你最喜欢画什么？","我想先说说今天的事。"]
        case "anime-torao": texts=["讲讲修理铺的谜题。","那个发条玩具怎么了？","我想先慢慢聊聊。"]
        case "anime-ichigo": texts=["我想试试你的新甜点。","先聊聊招牌配方吧。","猜猜我喜欢什么口味？"]
        case "anime-lime": texts=["Tell me about your greenhouse.","Let's practice English together.","What are you growing today?"]
        case "anime-mafuyu": texts=["旅舍最近有什么故事？","一起想想冬日茶单吧。","我想先聊聊今天。"]
        case "anime-nozomi": texts=["Tell me a star story.","What can we see tonight?","Let's practice English together."]
        case "anime-siska": texts=["一起看看那封信吧。","你发现了什么线索？","我想讲一件想留住的事。"]
        case "anime-plum": texts=["先陪我挑一杯茶吧。","庭院最近有什么变化？","我想和你聊聊今天。"]
        default: texts=[]
        }
        }
        return texts.enumerated().map { index,text in
            AIQuickReply(id:"opening-local-\(messageID)-\(index)",text:text,likelihood:1-Double(index)*0.2)
        }
    }
}
