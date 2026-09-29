import SwiftUI

struct TogetherPanel: View {
    let session: CompanionSession
    @State private var tab = "故事"
    @State private var preferences: TogetherPreferences
    @State private var mood = "平静"
    @State private var note = ""
    @State private var replay: CompanionStory?
    @State private var confirmReplay = false
    @State private var showMemory = false
    @State private var cloud: CompanionCloudFeature?
    @State private var childClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store:CompanionStore { session.store }
    private var model:ModelDescriptor { session.model }
    private var experience:CompanionExperiences { session.record.together }
    private var stories:[CompanionStory] { CompanionStory.available(for:model) }
    init(session:CompanionSession) {
        self.session = session
        _preferences = State(initialValue:session.record.together.preferences)
    }
    var body:some View {
        ZStack(alignment:.topLeading) {
            if showMemory {
                CompanionMemoryView(store:store,model:model)
                    .environment(\.softPanelCloseRequest,childClose)
                    .environment(\.softPanelDismiss,{ childClose.request() }).transition(.opacity)
            } else if let cloud {
                CompanionCloudPreview(feature:cloud)
                    .environment(\.softPanelCloseRequest,childClose)
                    .environment(\.softPanelDismiss,{ childClose.request() }).transition(.opacity)
            } else { content.transition(.opacity) }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .onAppear {
                prepareChildClose()
                close?.beforeClose = { store.saveTogether(preferences,id:model.id); return store.error == nil }
            }
            .onDisappear { close?.beforeClose = nil }
            .onChange(of:tab) { _,_ in store.saveTogether(preferences,id:model.id) }
            .confirmationDialog("从开场重新开始？已有聊天和手记会保留。",isPresented:$confirmReplay,titleVisibility:.visible) {
                Button("重新开始故事") { if let replay { session.beginStory(replay,replay:true) } }
            }
    }
    private func prepareChildClose() {
        // A close request is one-shot; every new child presentation needs a new cycle.
        childClose.begin { withAnimation(.easeInOut(duration:reduceMotion ? 0.15 : 0.25)) { showMemory = false; cloud = nil } }
    }
    private var content:some View {
        VStack(spacing:0) {
            PanelPageHeader("和\(session.record.profile.name)一起",subtitle:"把相处，变成自己的故事",backID:"closeTogetherButton")
            VStack(spacing:14) {
                Picker("一起",selection:$tab) {
                    ForEach(["故事","相处","时光","更多"],id:\.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("togetherTabs")
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        switch tab {
                        case "相处": relationship
                        case "时光": journal
                        case "更多": futureFeatures
                        default: storyShelf
                        }
                        if let error = store.error { Text(error).font(.caption).foregroundStyle(Theme.peach) }
                    }.padding(.bottom,28)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("togetherContent")
            }.padding(.horizontal,22)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .accessibilityElement(children:.contain).accessibilityIdentifier("togetherPanel")
    }
    private var storyShelf:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("一起写故事 · AI 即兴").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.secondary)
            ForEach(stories) { story in storyCard(story) }
            Text("故事进度只属于你和这个角色。随时暂停，回来接着聊；聊天和共同记忆不会被重置。")
                .font(.system(size:12)).lineSpacing(4).foregroundStyle(Theme.secondary)
        }
    }
    private func storyCard(_ story:CompanionStory) -> some View {
        let progress = experience.stories[story.id]
        let active = experience.activeStoryID == story.id
        return VStack(alignment:.leading,spacing:14) {
            HStack(spacing:12) {
                Image(systemName:story.symbol).font(.system(size:22,weight:.light)).foregroundStyle(Theme.peach)
                    .frame(width:42,height:42).background(Theme.peach.opacity(0.08),in:Circle())
                VStack(alignment:.leading,spacing:4) {
                    Text(story.title).font(.system(size:17,weight:.semibold,design:.rounded))
                    Text(story.category + " · " + (progress?.completed == true ? "已完成" : progress == nil ? "待开启" : "进度已保存"))
                        .font(.system(size:11)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength:0)
            }
            if active {
                Text("故事由你和角色共同创作，回到会话就可以接着聊。").font(.system(size:13)).foregroundStyle(Theme.secondary)
                Button("接着讲下去") { session.continueStory() }
                    .font(.system(size:13,weight:.medium)).disabled(session.generating)
                Button("先暂停") { store.pauseStory(id:model.id) }
                    .font(.system(size:11)).foregroundStyle(Theme.secondary)
            } else {
                Text(story.subtitle).font(.system(size:13)).lineSpacing(4).foregroundStyle(Theme.secondary)
                Button {
                    session.beginStory(story)
                } label: {
                    HStack { Text(progress == nil ? "开始故事" : progress?.completed == true ? "回看结局" : "继续故事"); Spacer(); Image(systemName:"arrow.up.right") }
                        .font(.system(size:13,weight:.medium)).frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("start-story-"+story.id)
            }
        }.padding(16).background(Theme.surface.opacity(0.78),in:RoundedRectangle(cornerRadius:21))
            .overlay(RoundedRectangle(cornerRadius:21).stroke(active ? Theme.accent.opacity(0.28) : Theme.line.opacity(0.45),lineWidth:0.7))
    }
    private var relationship:some View {
        VStack(alignment:.leading,spacing:18) {
            textEntry("希望怎么称呼你",placeholder:"你的专属称呼",text:$preferences.nickname,id:"togetherNickname")
            textEntry("让对方了解你",placeholder:"兴趣、近况，或想一起做的事",text:$preferences.aboutMe,id:"togetherAboutMe")
            VStack(alignment:.leading,spacing:9) {
                caption("我们的关系")
                Picker("我们的关系",selection:$preferences.relationship) {
                    ForEach(["朋友","搭档","知己"],id:\.self) { Text($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("togetherRelationship")
            }
            VStack(alignment:.leading,spacing:9) {
                caption("当我有心事时")
                Picker("回应偏好",selection:$preferences.responseStyle) {
                    ForEach(["先听我说","一起想办法","轻松聊聊"],id:\.self) { Text($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("togetherResponseStyle")
            }
            textEntry("暂时不想聊",placeholder:"关键词，用逗号分开",text:$preferences.avoidedTopics,id:"togetherAvoidedTopics")
            Text("只对当前角色生效，返回时保存。AI 会结合这些偏好理解和回应你。")
                .font(.caption).foregroundStyle(Theme.secondary).lineSpacing(3)
            Button {
                store.saveTogether(preferences,id:model.id)
                if store.error == nil { prepareChildClose();withAnimation(.easeInOut(duration:0.22)) { showMemory = true } }
            } label: {
                HStack(spacing:12) {
                    Image(systemName:"bookmark")
                    VStack(alignment:.leading,spacing:4) {
                        Text("共同记忆").font(.subheadline.weight(.medium))
                        Text("\(session.record.memories.count) 件已记住 · \(experience.suggestions.count) 件待确认").font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(); Image(systemName:"chevron.right").font(.caption)
                }.padding(15).background(Theme.surface.opacity(0.8),in:RoundedRectangle(cornerRadius:17))
            }.buttonStyle(.plain).accessibilityIdentifier("togetherMemoryButton")
        }
    }
    private var journal:some View {
        VStack(alignment:.leading,spacing:16) {
            let first = session.record.messages.map(\.date).min()
            let days = first.map { max(1,(Calendar.current.dateComponents([.day],from:Calendar.current.startOfDay(for:$0),to:Calendar.current.startOfDay(for:Date())).day ?? 0)+1) } ?? 0
            HStack(spacing:22) {
                statistic("\(days)","相遇天数")
                statistic("\(session.record.memories.count)","共同记忆")
                statistic("\(experience.stories.values.filter(\.completed).count)","完成故事")
                Spacer(minLength:0)
            }.padding(.vertical,6)
            VStack(alignment:.leading,spacing:12) {
                caption("今天，想留下什么？")
                Picker("心情",selection:$mood) { ForEach(["平静","开心","有点累","低落"],id:\.self) { Text($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("momentMood")
                TextField("记下一件小事…",text:$note,axis:.vertical).lineLimit(2...4)
                    .font(.system(size:14)).accessibilityIdentifier("momentInput")
                Button {
                    store.addMoment(id:model.id,mood:mood,text:note)
                    if store.error == nil { note = "" }
                } label: {
                    Text("留在时光里").font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,minHeight:44)
                        .background(Theme.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("saveMomentButton")
            }.padding(15).background(Theme.surface.opacity(0.8),in:RoundedRectangle(cornerRadius:18))
            if experience.moments.isEmpty {
                Text("第一段共同经历，从今天开始。完成的故事也会留在这里。")
                    .font(.system(size:13)).foregroundStyle(Theme.secondary).padding(.vertical,12)
            }
            ForEach(experience.moments.reversed()) { moment in
                HStack(alignment:.top,spacing:12) {
                    Image(systemName:moment.kind == "story" ? "sparkle" : "circle.dotted").font(.system(size:14)).foregroundStyle(Theme.peach).padding(.top,3)
                    VStack(alignment:.leading,spacing:7) {
                        Text(moment.title).font(.system(size:14,weight:.medium))
                        Text(moment.text).font(.system(size:13)).lineSpacing(4).foregroundStyle(Theme.secondary)
                        HStack {
                            Text(moment.date,format:.dateTime.month().day().hour().minute()).font(.system(size:10))
                            Spacer()
                            Button("删除") { store.removeMoment(moment.id,id:model.id) }.font(.system(size:11))
                                .frame(minHeight:36).accessibilityIdentifier("deleteMomentButton")
                        }.foregroundStyle(Theme.secondary)
                    }
                }.padding(.vertical,8).accessibilityElement(children:.contain).accessibilityIdentifier("togetherMoment")
            }
            Text("仅保存在此账号与角色的本机记录中。").font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
    private var futureFeatures:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("下一段相处").font(.system(size:20,weight:.semibold,design:.rounded))
            Text("先看看未来的玩法。这些服务尚未开通，当前不会连接或上传内容。")
                .font(.system(size:12)).lineSpacing(4).foregroundStyle(Theme.secondary)
            ForEach(CompanionCloudFeature.allCases) { feature in
                Button { prepareChildClose();withAnimation(.easeInOut(duration:0.22)) { cloud = feature } } label: {
                    HStack(spacing:14) {
                        Image(systemName:feature.symbol).font(.system(size:20,weight:.light)).frame(width:30)
                        VStack(alignment:.leading,spacing:5) {
                            Text(feature.title).font(.system(size:14,weight:.medium))
                            Text(feature.subtitle).font(.system(size:11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(); Text("预览").font(.system(size:10)).foregroundStyle(Theme.peach)
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Theme.surface.opacity(0.8),in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain).accessibilityIdentifier("cloud-feature-"+feature.rawValue)
            }
        }
    }
    private func caption(_ text:String) -> some View { Text(text).font(.system(size:12,weight:.medium)).foregroundStyle(Theme.secondary) }
    private func statistic(_ value:String,_ label:String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(value).font(.system(size:24,weight:.medium,design:.rounded)).monospacedDigit()
            caption(label)
        }
    }
    private func textEntry(_ title:String,placeholder:String,text:Binding<String>,id:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            caption(title)
            TextField(placeholder,text:text,axis:.vertical).lineLimit(1...4).font(.system(size:14))
                .padding(13).background(Theme.surface.opacity(0.8),in:RoundedRectangle(cornerRadius:13))
                .accessibilityIdentifier(id)
        }
    }
}
