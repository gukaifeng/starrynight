import Foundation

struct TogetherPreferences: Codable, Equatable, Sendable {
    var nickname = ""
    var aboutMe = ""
    var relationship = "朋友"
    var responseStyle = "先听我说"
    var avoidedTopics = ""
    var normalized: Self {
        var value = self
        value.nickname = String(nickname.trimmingCharacters(in:.whitespacesAndNewlines).prefix(20))
        value.aboutMe = String(aboutMe.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
        value.avoidedTopics = String(avoidedTopics.trimmingCharacters(in:.whitespacesAndNewlines).prefix(200))
        if !["朋友","搭档","知己"].contains(relationship) { value.relationship = "朋友" }
        if !["先听我说","一起想办法","轻松聊聊"].contains(responseStyle) { value.responseStyle = "先听我说" }
        return value
    }
    func avoids(_ input:String) -> Bool {
        avoidedTopics.components(separatedBy:CharacterSet(charactersIn:",，、;；\n"))
            .map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
            .contains { $0.count >= 2 && input.localizedCaseInsensitiveContains($0) }
    }
}

struct MemorySuggestion: Codable, Identifiable, Sendable {
    var id = UUID()
    let sourceMessageID: UUID
    let text: String
    var date = Date()
}
struct TogetherMoment: Codable, Identifiable, Sendable {
    var id = UUID()
    var kind: String
    var title: String
    var text: String
    var date = Date()
}
struct StoryProgress: Codable, Equatable, Sendable {
    let storyID: String
    var revision = 1
    var nodeID = "start"
    var choices: [String] = []
    var completed = false
    var updatedAt = Date()
}
struct CompanionExperiences: Codable, Sendable {
    var preferences = TogetherPreferences()
    var stories: [String:StoryProgress] = [:]
    var activeStoryID: String? = nil
    var moments: [TogetherMoment] = []
    var suggestions: [MemorySuggestion] = []
    // Stable source IDs prevent ignored candidates from reappearing on replay.
    var reviewedMemorySources: [UUID] = []
}
extension CharacterRecord {
    var together: CompanionExperiences { experiences ?? CompanionExperiences() }
}

struct CompanionStory: Identifiable, Sendable {
    struct Choice: Identifiable, Sendable { let id, title, next: String }
    struct Node: Sendable { let title, text: String; let choices: [Choice] }
    let id, title, subtitle, category, symbol: String
    let nodes: [String:Node]
    func node(_ progress:StoryProgress?) -> Node { nodes[progress?.nodeID ?? "start"] ?? nodes["start"]! }
    func text(_ node:Node, name:String) -> String { node.text.replacingOccurrences(of:"{name}",with:name) }
    static let all: [Self] = [
        .init(id:"rain-letter",title:"雨夜来信",subtitle:"一封没有署名的信，等你决定去向。",category:"日常",symbol:"envelope.open",
            nodes:[
                "start":.init(title:"窗边的信",text:"雨声落在窗沿。我是{name}，今晚故事里和你一起值班的人。桌上有一封没署名的信，封面写着：‘给还没睡的人。’我们先读，还是先找寄信的人？",choices:[
                    .init(id:"read",title:"一起拆开信",next:"read"),.init(id:"find",title:"去找寄信的人",next:"find")]),
                "read":.init(title:"未写完的愿望",text:"信里是一张空白车票，背面写着：‘有一天，我想去看海。’我把台灯转向纸面。我们替这位陌生人写一封回信，还是把自己的愿望也放进去？",choices:[
                    .init(id:"reply",title:"给陌生人写回信",next:"reply-end"),.init(id:"wish",title:"留下我们的愿望",next:"wish-end")]),
                "find":.init(title:"门口的伞",text:"门口只剩一把还在滴水的伞，伞柄系着书店的便签。店已经打烊了。我们留下纸条约明天再见，还是把信带回窗边慢慢读？",choices:[
                    .init(id:"meet",title:"约明天再见",next:"meet-end"),.init(id:"return",title:"回到窗边读信",next:"read")]),
                "reply-end":.init(title:"送给明天的回信",text:"我们写下：‘愿你总有出发的一天。’信封被放回门边，雨也小了。我记住了故事里的这一晚：我们一起把陌生人的愿望，认真接住了。",choices:[]),
                "wish-end":.init(title:"同一张车票",text:"我们把两个愿望写在车票背面，没有给它们设期限。我合上信封，留出下一次的空白。这个故事的结尾，是我们允许未来慢慢到来。",choices:[]),
                "meet-end":.init(title:"明天见",text:"纸条上只有‘明天见，我们会等书店开门’。我们收好伞，关上灯。这一晚没有解开所有谜题，却留下了一个温柔的约定。",choices:[])
            ]),
        .init(id:"after-class",title:"放学后的天台",subtitle:"风掀开了画册，今天还没结束。",category:"校园",symbol:"sun.horizon",
            nodes:[
                "start":.init(title:"最后一节课之后",text:"在这个校园故事里，我叫{name}，是和你一起收拾画室的同学。天台的门开着，长椅上放着一本没画完的画册。要画晚霞，还是看看夹在里面的纸条？",choices:[
                    .init(id:"draw",title:"一起画晚霞",next:"draw"),.init(id:"note",title:"看看那张纸条",next:"note")]),
                "draw":.init(title:"天空的颜色",text:"我递给你两支铅笔，问：‘今天的天空，你想留住哪种颜色？’我们可以把画送给明天的自己，也可以贴在画室，让路过的人都看见。",choices:[
                    .init(id:"keep",title:"留给明天的自己",next:"keep-end"),.init(id:"share",title:"贴在画室墙上",next:"share-end")]),
                "note":.init(title:"一句没说出口的话",text:"纸条写着：‘其实我很喜欢这里。’风很轻。我说，有些话不用急着找到主人。我们替它画上晚霞，还是把它好好夹回去？",choices:[
                    .init(id:"color",title:"给纸条画上晚霞",next:"share-end"),.init(id:"safe",title:"轻轻夹回画册",next:"keep-end")]),
                "keep-end":.init(title:"把今天留好",text:"我们把画册收进柜子，约好下次接着画。楼下响起关门铃，晚霞还在。今天的故事停在这里，没完成的部分也值得被保留。",choices:[]),
                "share-end":.init(title:"一面小小的天空",text:"我们把画贴在墙上，旁边留了两支笔。也许明天会有人添一朵云。我笑着说：‘这样，我们的晚霞就有了新的朋友。’",choices:[])
            ]),
        .init(id:"star-signal",title:"星海来客",subtitle:"一段遥远的信号，两个人的选择。",category:"幻想",symbol:"sparkle",
            nodes:[
                "start":.init(title:"第七频道",text:"欢迎登上故事里的观测站。我是{name}，你的值夜搭档。第七频道突然传来三下敲击声，像是有人在很远的地方敲门。我们先回应，还是一起解码？",choices:[
                    .init(id:"answer",title:"回敲三下",next:"answer"),.init(id:"decode",title:"一起解码信号",next:"decode")]),
                "answer":.init(title:"宇宙另一端",text:"对方回应了一小段旋律，星图上亮起一个坐标。我把音量调低：‘它好像只是想确认，有人在听。’我们送一首新的旋律，还是发出地球的雨声？",choices:[
                    .init(id:"melody",title:"送出一段旋律",next:"music-end"),.init(id:"rain",title:"送出地球的雨声",next:"rain-end")]),
                "decode":.init(title:"一张声音地图",text:"我们发现这不是求救信号，而是一份记录故乡声音的地图。最后一格还是空的。填上我们即兴的旋律，还是窗外模拟的雨声？",choices:[
                    .init(id:"compose",title:"为它补一段旋律",next:"music-end"),.init(id:"home",title:"让它听见雨声",next:"rain-end")]),
                "music-end":.init(title:"回声里的合奏",text:"旋律在星图间回荡，对方加了一个轻轻的和音。我们没见到那位来客，却完成了一次合奏。值班日志里，我写下：‘今晚，宇宙有了回声。’",choices:[]),
                "rain-end":.init(title:"宇宙听见了雨",text:"雨声传出去很久，对方才回应：‘原来这就是你们的家。’我们把信号存进日志。这次故事里最远的一段旅程，是一场雨的声音。",choices:[])
            ])
    ]
    static func available(for model:ModelDescriptor) -> [Self] {
        let ids: [String]
        switch model.runtimeID {
        case "anime-shino","anime-fumiriya": ids = ["after-class","rain-letter"]
        case "studio-robot","anime-vita": ids = ["star-signal","rain-letter"]
        case "hatsune-miku": ids = ["after-class","star-signal"]
        default: ids = ["rain-letter","star-signal"]
        }
        return ids.compactMap { id in all.first { $0.id == id } }
    }
}

enum StoryEngine {
    struct Transition: Sendable { let progress:StoryProgress; let userText, reply:String; let ending:String? }
    static func choose(_ choiceID:String, nodeID:String, story:CompanionStory, progress:StoryProgress,
                       name:String, now:Date = Date()) -> Transition? {
        guard progress.storyID == story.id, progress.revision == 1, !progress.completed,
              progress.nodeID == nodeID, let node = story.nodes[nodeID],
              let choice = node.choices.first(where:{ $0.id == choiceID }), let next = story.nodes[choice.next] else { return nil }
        var updated = progress; updated.nodeID = choice.next; updated.choices.append(choice.id)
        updated.completed = next.choices.isEmpty; updated.updatedAt = now
        return Transition(progress:updated,userText:choice.title,reply:story.text(next,name:name),ending:updated.completed ? next.title : nil)
    }
}

enum MemoryCandidates {
    static func extract(_ message:CompanionMessage,record:CharacterRecord) -> MemorySuggestion? {
        guard message.role == "user", message.storyID == nil else { return nil }
        let text = message.text.trimmingCharacters(in:.whitespacesAndNewlines)
        let markers = ["我喜欢","我最喜欢","我的爱好是","我的目标是","我希望你叫我","请记住：","记住："]
        guard (4...150).contains(text.count), markers.contains(where:{ text.hasPrefix($0) }),
              !text.contains("？"), !text.contains("?"), !record.together.preferences.avoids(text),
              !record.memories.contains(where:{ $0.text == text }),
              !record.together.suggestions.contains(where:{ $0.text == text || $0.sourceMessageID == message.id }),
              !record.together.reviewedMemorySources.contains(message.id) else { return nil }
        return MemorySuggestion(sourceMessageID:message.id,text:text,date:message.date)
    }
}

/// Versioned value passed to a future provider. Unconfirmed suggestions never enter it.
struct CompanionContextV1: Codable, Sendable {
    let version: Int
    let characterID, characterName, characterBackground, characterPersonality, characterTone: String
    let preferences: TogetherPreferences
    let confirmedMemories: [String]
    let activeStory: StoryProgress?
    init(characterID:String,record:CharacterRecord) {
        version = 1; self.characterID = characterID; characterName = record.profile.name
        characterBackground = record.profile.background; preferences = record.together.preferences.normalized
        characterPersonality = record.profile.personality; characterTone = record.profile.tone
        confirmedMemories = record.memories.suffix(30).map(\.text)
        activeStory = record.together.activeStoryID.flatMap { record.together.stories[$0] }
    }
}

enum LocalTogetherDialogue {
    static func override(_ input:String,record:CharacterRecord) -> DialogueReply? {
        let p = record.together.preferences.normalized
        var text:String?
        if p.avoids(input) { text = "这个话题你设成了暂时不聊，我们换一个吧。想说说今天的小事，还是一起开始一个故事？" }
        else if input.contains("我们的关系") || input.contains("你怎么称呼我") {
            text = "我们按你喜欢的方式，以\(p.relationship)的身份相处。" + (p.nickname.isEmpty ? "你也可以告诉我，希望怎么称呼你。" : "我会叫你\(p.nickname)。")
        } else if input.contains("你了解我") && !p.aboutMe.isEmpty { text = "你告诉过我：\(p.aboutMe)。如果想法变了，我们随时可以更新。" }
        else if input.contains("继续故事"), let id = record.together.activeStoryID,
                let story = CompanionStory.all.first(where:{ $0.id == id }), let progress = record.together.stories[id] {
            let node = story.node(progress)
            text = progress.completed ? "《\(story.title)》已经完成，可以在‘一起’里重玩或选择新故事。" : "我们停在《\(story.title)》的‘\(node.title)’。下一步可以\(node.choices.map(\.title).joined(separator:"，或"))。到‘一起’里选一个，我们接着走。"
        } else if ["难过","有点累","烦恼","压力"].contains(where:input.contains), record.experiences != nil {
            switch p.responseStyle {
            case "一起想办法": text = "我们先选一件最困扰你的事，把它拆成今天能做的一小步。你愿意从哪件事说起？"
            case "轻松聊聊": text = "先给自己留一点空白吧。我们可以聊聊喜欢的歌，或者想象一个舒服的周末，你选。"
            default: text = "我在听，不急着给建议。你想从哪里说起，就从哪里开始。"
            }
        }
        return text.map { DialogueReply(text:$0,eventName:"dialogue.reply",emotion:"neutral") }
    }
}
