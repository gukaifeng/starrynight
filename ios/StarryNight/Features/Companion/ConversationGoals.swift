import SwiftUI

struct ConversationGoalConfig: Codable, Equatable, Sendable {
    var mode = "relationship"
    var initialRelation = "friends"
    var longTerm = "friendship"
    var shortTerm = ""
    var task = "study"
    var paused = false
    var confirmedCouple = false
    var extensions: [String:JSONValue]? = nil
    var branch: String {
        mode == "task" ? "task:"+task : mode == "sandbox" ? "sandbox" : "relationship:"+initialRelation+":"+longTerm
    }
}
struct ConversationGoalBranch: Codable, Sendable {
    let familiarity, trust, affection, taskProgress: Double
    let milestones: [String]?
}
struct ConversationGoals: Codable, Sendable {
    let schemaVersion: Int
    var version: Int
    let progressVersion: Int
    let romanceAllowed: Bool
    var config: ConversationGoalConfig
    let branches: [String:ConversationGoalBranch]
    var bond: ConversationGoalBranch? = nil
    static func initial(_ id:String) -> Self {
        let romance = ["anime-mafuyu","anime-ichigo"].contains(id)
        var config = ConversationGoalConfig();config.longTerm = romance ? "romance" : "friendship"
        if ["anime-lime","anime-nozomi"].contains(id) {config.mode="task";config.task="english"}
        return .init(schemaVersion:1,version:0,progressVersion:0,romanceAllowed:romance,config:config,branches:[:])
    }
    // API decoding uses convertFromSnakeCase; local records use default Codable.
    func wireConfig() throws -> JSONValue {
        let encoder = JSONEncoder();encoder.keyEncodingStrategy = .convertToSnakeCase
        return try JSONDecoder().decode(JSONValue.self,from:encoder.encode(config))
    }
}

struct ConversationGoalsPanel: View {
    let session: CompanionSession
    @State private var snapshot: ConversationGoals
    @State private var config: ConversationGoalConfig
    @State private var loading = false
    @State private var notice: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(session:CompanionSession) {
        self.session = session
        let value = session.record.together.goals ?? .initial(session.model.id)
        _snapshot = State(initialValue:value);_config = State(initialValue:value.config)
    }
    private let modes = [("relationship","心向彼此","让感情有一条可以慢慢走的路","heart"),
                         ("task","一起成长","有价值的陪伴，也有自己的温度","book"),
                         ("sandbox","随心相处","不用赶往结局，聊到哪里都可以","sparkle")]
    private var shorts: [String] {
        config.mode == "relationship" ? (snapshot.romanceAllowed ? ["慢慢了解彼此","今天想约会","想被安慰","聊聊我们的分歧"] : ["慢慢了解彼此","想被安慰","一起做件小事","聊聊我们的分歧"]) :
        config.mode == "task" ? ["帮我进入状态","自然纠正我的表达","一起解决一个问题","给我一点鼓励"] : ["随便聊聊","分享今天的小事","了解我的喜好","一起找点新鲜事"]
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("今天，想和对方走向哪里？").font(.system(size:19,weight:.medium,design:.serif))
            VStack(spacing:8) {
                ForEach(modes,id:\.0) { mode in
                    Button {
                        withAnimation(.easeInOut(duration:reduceMotion ? 0.1 : 0.25)) { config.mode = mode.0;config.shortTerm = "" }
                    } label: {
                        HStack(spacing:12) {
                            Image(systemName:mode.3).font(.system(size:16,weight:.light)).frame(width:25)
                            VStack(alignment:.leading,spacing:4) {
                                Text(LocalizedStringKey(mode.1)).font(.system(size:14,weight:.medium))
                                Text(LocalizedStringKey(mode.2)).font(.system(size:11)).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength:0)
                            if config.mode == mode.0 { Image(systemName:"checkmark").font(.system(size:12)) }
                        }.padding(13).frame(maxWidth:.infinity,alignment:.leading)
                            .background(Theme.surface.opacity(config.mode == mode.0 ? 0.95 : 0.55),in:RoundedRectangle(cornerRadius:16))
                            .overlay(RoundedRectangle(cornerRadius:16).stroke(Theme.peach.opacity(config.mode == mode.0 ? 0.35 : 0.06),lineWidth:0.7))
                    }.buttonStyle(.plain).accessibilityIdentifier("goal-mode-"+mode.0)
                }
            }
            if config.mode == "relationship" {
                row("初始关系") {
                    Picker("初始关系",selection:$config.initialRelation) {
                        ForEach(relations,id:\.0) { Text(LocalizedStringKey($0.1)).tag($0.0) }
                    }.accessibilityIdentifier("goalInitialRelation")
                }
                row("长期方向") {
                    Picker("长期方向",selection:$config.longTerm) {
                        if snapshot.romanceAllowed { Text("从心动到相爱").tag("romance") }
                        Text("成为重要的朋友").tag("friendship")
                        Text("更懂彼此").tag("understanding")
                    }.accessibilityIdentifier("goalLongTerm")
                }
                if snapshot.romanceAllowed && config.longTerm == "romance" {
                    Toggle("我们已明确确认恋人关系",isOn:$config.confirmedCouple).font(.system(size:12))
                        .accessibilityIdentifier("goalConfirmCouple")
                    Text("亲近会慢慢发展；关系确认由你决定，也可以随时暂停这条路线。")
                        .font(.system(size:11)).foregroundStyle(Theme.secondary)
                }
            } else if config.mode == "task" {
                row("想一起做的事") {
                    Picker("任务",selection:$config.task) {
                        Text("陪我学习").tag("study");Text("练习英语口语").tag("english")
                        Text("倾听与整理心事").tag("listening");Text("一起做计划").tag("planning")
                    }.accessibilityIdentifier("goalTask")
                }
                Text("先回应你想表达的内容，再自然地帮你改进；保留角色的说话方式。")
                    .font(.system(size:11)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment:.leading,spacing:9) {
                Text("这次相处的小愿望").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.secondary)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                    ForEach(shorts,id:\.self) { value in
                        Button { config.shortTerm = value } label: {
                            Text(LocalizedStringKey(value)).font(.system(size:11)).frame(maxWidth:.infinity,minHeight:34)
                                .background(Theme.peach.opacity(config.shortTerm == value ? 0.15 : 0.04),in:Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                TextField("也可以写下自己的方向",text:$config.shortTerm,axis:.vertical).lineLimit(1...3)
                    .font(.system(size:13)).padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
                    .accessibilityIdentifier("goalShortTerm")
            }
            Toggle("暂停推进，保留进展",isOn:$config.paused).font(.system(size:12)).accessibilityIdentifier("goalPause")
            if let branch = snapshot.branches[config.branch],let milestones = branch.milestones,!milestones.isEmpty {
                Text("一起留下的变化").font(.system(size:13,weight:.medium,design:.serif))
                Text(milestones.map { milestoneNames[$0] ?? $0 }.joined(separator:" · "))
                    .font(.system(size:12)).foregroundStyle(Theme.secondary).accessibilityIdentifier("goalMilestones")
            }
            Text("换一种相处，原有聊天、共同记忆与其他分支的进展仍会保留。")
                .font(.system(size:11)).lineSpacing(3).foregroundStyle(Theme.secondary)
            Button { Task { await save() } } label: {
                HStack { Text(loading ? "正在连接…" : "按这个方向相处");Spacer();Image(systemName:"arrow.right") }
                    .font(.system(size:13,weight:.medium)).padding(14).background(Theme.peach.opacity(0.12),in:RoundedRectangle(cornerRadius:14))
            }.buttonStyle(.plain).disabled(loading).accessibilityIdentifier("saveConversationGoal")
            if let notice { Text(LocalizedStringKey(notice)).font(.system(size:11)).foregroundStyle(Theme.secondary).accessibilityIdentifier("goalNotice") }
        }.task { await load() }
            .onChange(of:config.initialRelation) { _, value in
                if ["pursuit","flirting","lovers"].contains(value) {config.longTerm="romance"}
            }
    }
    private var relations:[(String,String)] {
        [("strangers","初识"),("friends","朋友"),("mentor","师徒"),("rivals","宿敌"),("childhood","青梅竹马")]
            + (snapshot.romanceAllowed ? [("pursuit","追求"),("flirting","暧昧"),("lovers","恋人")] : [])
    }
    private let milestoneNames = ["shared_interest":"发现共同喜好","trust_opened":"愿意分享心事","date_agreed":"约好了见面","repair":"化解一次分歧","learning_step":"一起学会了一点","preference_understood":"更了解你的选择"]
    private func row<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        HStack {Text(LocalizedStringKey(title)).font(.system(size:12)).foregroundStyle(Theme.secondary);Spacer();content().font(.system(size:12))}
    }
    @MainActor private func decode(_ value:JSONValue) throws -> ConversationGoals {
        let decoder = JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ConversationGoals.self,from:JSONEncoder().encode(value))
    }
    @MainActor private func remember(_ value:ConversationGoals) {
        session.store.update(session.model.id) { record in var experience=record.together;experience.goals=value;record.experiences=experience }
    }
    @MainActor private func load() async {
        guard let account=PlatformAPI.shared.activeSession,account.user.id==session.store.accountID else {notice="登录后可同步相处方向。";return}
        loading=true;defer{loading=false}
        do {
            let value=try await PlatformAPI.shared.request("GET","/v1/conversations/"+session.model.id+"/goals",token:account.token)
            guard PlatformAPI.shared.activeSession?.token==account.token else{return}
            snapshot=try decode(value);config=snapshot.config;remember(snapshot)
        } catch {notice=error.localizedDescription}
    }
    @MainActor private func save() async {
        guard let account=PlatformAPI.shared.activeSession,account.user.id==session.store.accountID else {session.requestLogin();return}
        loading=true;notice=nil;defer{loading=false}
        config.shortTerm=String(config.shortTerm.trimmingCharacters(in:.whitespacesAndNewlines).prefix(160))
        if config.longTerm != "romance" {config.confirmedCouple=false}
        do {
            let body:JSONValue = .object(["expected_version":.number(Double(snapshot.version)),"config":try snapshotWithConfig(),
                "conversation_reset":.string(session.record.conversationResetID ?? "")])
            let value=try await PlatformAPI.shared.request("PUT","/v1/conversations/"+session.model.id+"/goals",token:account.token,body:body)
            guard PlatformAPI.shared.activeSession?.token==account.token else{return}
            snapshot=try decode(value);config=snapshot.config;remember(snapshot);session.goalDirectionChanged();notice="方向已保存，下一句话从这里继续。"
        } catch {notice=error.localizedDescription}
    }
    private func snapshotWithConfig() throws -> JSONValue {var value=snapshot;value.config=config;return try value.wireConfig()}
}
