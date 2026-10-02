#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct AppLanguageFixture: View {
    @State private var session: CompanionSession
    @State private var checks = ""
    init() {
        AppLanguageSettings.shared.selection = "zh-Hans"
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("language-"+UUID().uuidString)
        let store=CompanionStore(storageURL:folder.appendingPathComponent("journal.json"),arguments:[])
        let model=ModelDescriptor.all.first!, id=UUID()
        let parts=[AIReplyPart(kind:"dialogue",text:"Good morning!\nHow was your day?",at:0),
                   AIReplyPart(kind:"thought",text:"I hope you feel welcome.",at:0.5),
                   AIReplyPart(kind:"narration",text:"A small, gentle wave.",at:0.7)]
        let script=AIScript(messageId:id.uuidString,characterId:model.id,text:parts[0].text,
            beats:[AIBeat(beatId:"b",narrations:[],visuals:[],parts:parts)])
        var message=CompanionMessage(id:id,role:"assistant",text:script.text,aiScript:script)
        let source=ReplyTranslation.segments(message), fingerprint=ReplyTranslation.fingerprint(source)
        message.translations=[:]
        for language in [AppLanguage.simplified,.traditional] {
            let text = language == .simplified ? ["早上好！\n今天过得怎么样？","我希望你能感到安心。","轻轻挥了挥手。"] : ["早上好！\n今天過得怎麼樣？","我希望你能感到安心。","輕輕揮了揮手。"]
            message.translations?[language.rawValue]=MessageTranslation(sourceFingerprint:fingerprint,targetLanguage:language.rawValue,
                segments:zip(source,text).map {TranslationSegment(id:$0.id,kind:$0.kind,text:$1)})
        }
        var user=CompanionMessage(role:"user",text:"I would love to hear your story.")
        let userSource=ReplyTranslation.segments(user)
        user.translations=[AppLanguage.simplified.rawValue:MessageTranslation(sourceFingerprint:ReplyTranslation.fingerprint(userSource),targetLanguage:AppLanguage.simplified.rawValue,
            segments:[.init(id:"text",kind:"dialogue",text:"我很想听听你的故事。")])]
        store.update(model.id) {$0.messages=[user,message]}
        _session=State(initialValue:CompanionSession(store:store,model:model,soundscape:CompanionSoundscape()))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:14) {
                Text("消息").accessibilityIdentifier("localizedTitle")
                Text(checks).font(.caption2).accessibilityIdentifier("languageCoreResult")
                NavigationLink {AppLanguageSettingsView()} label:{Label("语言",systemImage:"globe")}
                    .accessibilityIdentifier("fixtureLanguageSettings")
                CompanionChatView(session:session).frame(height:380)
                Text("原文").accessibilityIdentifier("localizedOriginalLabel")
            }.padding(16).background(Theme.background).foregroundStyle(Theme.ink)
                .navigationTitle("设置").task {checks=Self.check();session.requestQuickReplies()}
        }.preferredColorScheme(.dark)
    }
    private static func check() -> String {
        func require(_ value:Bool,_ message:String) throws {if !value {throw NSError(domain:message,code:1)}}
        do {
            for (system,expected) in [("zh-CN",AppLanguage.simplified),("zh-SG",.simplified),("zh-HK",.traditional),("zh-Hant-TW",.traditional),("en-GB",.english),("ja-JP",.simplified),("fr-FR",.simplified)] {
                try require(AppLanguage.resolve("system",preferredLanguages:[system,"en"])==expected,"System fallback: "+system)
            }
            try require(AppLanguage.resolve("en",preferredLanguages:["zh-Hans"]) == .english,"Explicit selection")
            let defaults=UserDefaults(suiteName:"language-check-"+UUID().uuidString)!
            let one=AppLanguageSettings(defaults:defaults,preferredLanguages:["de"])
            try require(one.selection=="system" && one.resolved == .simplified,"Default language")
            one.selection="zh-Hant"
            try require(AppLanguageSettings(defaults:defaults).resolved == .traditional,"Relaunch persistence")
            for language in AppLanguage.allCases {
                let text=L10n.bundle(language).localizedString(forKey:"消息",value:nil,table:nil)
                try require(text == (language == .english ? "Messages" : "消息"),"Missing bundled catalog")
            }
            let english=[TranslationSegment(id:"1",kind:"dialogue",text:"Good morning. How are you feeling today?")]
            try require(ReplyTranslation.needed(english,target:.simplified) && !ReplyTranslation.needed(english,target:.english),"English detection")
            try require(ReplyTranslation.needed([.init(id:"mixed",kind:"dialogue",text:"我想练习 I would like a quiet evening 这样的表达。")],target:.simplified),"Substantial mixed English needs translation")
            let chinese=[TranslationSegment(id:"1",kind:"dialogue",text:"今天我们一起听音乐，聊聊你的梦想吧。")]
            try require(ReplyTranslation.needed(chinese,target:.traditional) && !ReplyTranslation.needed(chinese,target:.simplified),"Chinese script detection")
            let punctuation=[TranslationSegment(id:"1",kind:"dialogue",text:"…✨")]
            try require(!ReplyTranslation.needed(punctuation,target:.english),"Punctuation isn't a language")
            let nested=ReplyDisplayText.pieces("不只是花哦。（轻翻着手账本，（眼睛变得亮晶晶）\n唇角噙着温柔笑意）像雨后的痕迹。")
            try require(nested.count==3 && nested[1].aside && !nested[1].text.contains("（") && nested[1].text.contains("唇角"),"Nested aside must remain one styled region")
            try require(ReplyDisplayText.pieces("当然可以（我想试试看").last?.aside==true,"Unclosed aside remains styled")
            let reported="（我头都晕了，好过分）\n（露出一点小小不满）\n你是不是晃上瘾了！（扶着额头，）\n（神情变得轻松愉快）\n故作痛苦）\n再晃我可就要罢工，不让你试吃了。"
            let plain=ReplyDisplayText.pieces(reported).filter{!$0.aside}.map(\.text).joined()
            try require(!plain.contains("故作痛苦") && !plain.contains("扶着额头") && plain.contains("再晃我可就要罢工"),"Reported orphan action stays nonverbal")
            let broken=[AIReplyPart(kind:"dialogue",text:"你是不是晃上瘾了！（扶着额头，",at:0),
                AIReplyPart(kind:"narration",text:"神情变得轻松愉快",at:0.5),
                AIReplyPart(kind:"dialogue",text:"故作痛苦）再晃我可就要罢工了。",at:0.5)]
            let fixed=ReplyDisplayText.repaired(broken)
            try require(fixed.count==broken.count && fixed[1].text==broken[1].text && fixed[2].at==broken[2].at,"Repair preserves part indexes and reveal timing")
            try require(ReplyDisplayText.pieces(fixed[2].text).first?.aside==true,"Closing fragment retains annotation depth across structured narration")
            try require(ReplyDisplayText.pieces("你说得对）").map(\.text).joined()=="你说得对","Orphan glyph removed without deleting speech")
            try require(ReplyDisplayText.pieces("好呀（揉着额头)").last?.aside==true,"Mixed width parentheses")
            try require(ReplyDisplayText.needsSpeechRepair(reported) && !ReplyDisplayText.needsSpeechRepair("明天（如果有空）再聊。") && !ReplyDisplayText.needsSpeechRepair("维生素（B12）是这个名字。"),"Selective old-audio invalidation")
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("annotation-cache-"+UUID().uuidString)
            defer {try? FileManager.default.removeItem(at:folder)}
            let cache=SpeechClipCache(directory:folder), scope="annotation-fixture"
            let script=AIScript(messageId:"legacy",characterId:"fixture",text:reported,
                beats:[AIBeat(beatId:"b",dialogue:.init(text:reported),narrations:[],visuals:[])])
            let old=cache.key(scope:scope,text:"legacy|b",speed:1), repaired=cache.key(scope:scope,text:"legacy|b",speed:1,repair:true)
            let unrelated=cache.key(scope:scope,text:"other|b",speed:1)
            try require(old != repaired && unrelated==cache.key(scope:scope,text:"other|b",speed:1,repair:false),"Normal clip keys remain compatible")
            for key in [old,repaired,unrelated] {cache.insert(Data([1,2]),key:key)}
            cache.removeConversation(scope:scope,messages:[CompanionMessage(role:"assistant",text:reported,aiScript:script)])
            try require(cache.data(old)==nil && cache.data(repaired)==nil && cache.data(unrelated) != nil,"Reset removes both legacy and repaired audio, preserving other conversations")
            return "PASS: system fallback, explicit preference, relaunch, 3 catalogs, language detection"
        } catch {return "FAIL: \(error)"}
    }
}
#endif
