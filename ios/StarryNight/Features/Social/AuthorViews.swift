import SwiftUI

struct AuthorAvatar: View {
    let author: AuthorProfile
    var size: CGFloat = 48
    private var symbol: String {
        ["moon":"moon.stars", "leaf":"leaf", "sparkle":"sparkle", "sun":"sun.horizon", "cloud":"cloud", "wave":"water.waves"][author.avatar] ?? "moon.stars"
    }
    private var tint: Color {
        ["moon":Color(hex:0xBDCADD), "leaf":Color(hex:0xA8C9B6), "sparkle":Color(hex:0xDCC1BD), "sun":Color(hex:0xDEC393), "cloud":Color(hex:0xC8C7D7), "wave":Color(hex:0xA0CAD2)][author.avatar] ?? Theme.accent
    }
    var body: some View {
        ZStack {
            if author.isBuiltin { Image("BrandMark").resizable().scaledToFit().padding(size * 0.1) }
            else {
                Circle().fill(LinearGradient(colors:[tint.opacity(0.28),Theme.surface],startPoint:.topLeading,endPoint:.bottomTrailing))
                Image(systemName:symbol).font(.system(size:size * 0.4,weight:.light)).foregroundStyle(tint)
            }
        }.frame(width:size,height:size).background(Theme.surface,in:Circle()).clipShape(Circle())
            .overlay(Circle().stroke(tint.opacity(0.22),lineWidth:0.7)).accessibilityHidden(true)
    }
}

struct AuthorFollowButton: View {
    let author: AuthorProfile
    let library: CharacterLibrary
    private var followed: Bool { library.followedAuthors.contains(author.id) }
    var body: some View {
        if library.currentAuthor?.id == author.id {
            Text("这是你").font(.system(size:11)).foregroundStyle(Theme.secondary).padding(.horizontal,12).frame(height:44)
        } else {
            Button { library.followAuthor(author.id,!followed) } label: {
                ProfileRelationshipLabel(title:followed ? "已关注" : "关注",selected:followed)
            }.buttonStyle(.plain).accessibilityIdentifier("followAuthor-"+author.id)
                .accessibilityValue(followed ? "已关注" : "未关注")
                .accessibilityHint(followed ? "取消关注作者，已订阅的角色保持不变" : "关注作者，角色需要分别订阅")
        }
    }
}

struct AuthorRows: View {
    let authors: [AuthorProfile]
    let library: CharacterLibrary
    var onOpen: (String) -> Void
    var body: some View {
        LazyVStack(spacing:0) {
            ForEach(authors) { author in
                HStack(spacing:12) {
                    Button { onOpen(author.id) } label: {
                        HStack(spacing:12) {
                            AuthorAvatar(author:author,size:46)
                            VStack(alignment:.leading,spacing:6) {
                                HStack(spacing:6) {
                                    Text(author.name).font(.system(size:14,weight:.medium)).lineLimit(1)
                                    if author.isBuiltin { Text("内置").font(.system(size:9)).foregroundStyle(Theme.peach) }
                                }
                                Text(author.bio).font(.system(size:11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Text("\(library.publicWorks(by:author.id).count) 个公开角色").font(.system(size:10)).foregroundStyle(Theme.secondary.opacity(0.8))
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("openAuthor-"+author.id)
                    AuthorFollowButton(author:author,library:library)
                }.padding(.vertical,14)
                    .overlay(alignment:.bottom) { Rectangle().fill(Theme.line.opacity(0.4)).frame(height:0.5).padding(.leading,58) }
            }
        }
    }
}

enum AuthorDirectoryKind {
    case following, followers(String)
    var title: String { if case .following = self { "关注的作者" } else { "关注者" } }
}
struct AuthorDirectoryPanel: View {
    let kind: AuthorDirectoryKind
    let library: CharacterLibrary
    let store: CompanionStore
    let portraits: CharacterPortraitStore
    var onOpenCharacter: (String,Bool) -> Void
    @State private var selected: String?
    @State private var query = ""
    @State private var childClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: Animation { .easeInOut(duration:reduceMotion ? 0.1 : 0.25) }
    private var all: [AuthorProfile] {
        switch kind {
        case .following: library.followedAuthors.compactMap { library.author($0) }
        case .followers(let id): library.followers(of:id)
        }
    }
    var body: some View {
        ZStack {
            if let selected {
                AnyView(AuthorProfilePanel(authorID:selected,library:library,store:store,portraits:portraits,onOpenCharacter:onOpenCharacter))
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{ childClose.request() })
                    .transition(.opacity)
            } else {
                VStack(spacing:0) {
                    PanelPageHeader(kind.title,backID:"closeAuthorsButton")
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(Theme.secondary)
                        TextField("搜索作者",text:$query).font(.subheadline).accessibilityIdentifier("authorListSearch")
                    }.padding(12).background(Theme.surface,in:Capsule()).padding(.horizontal,22).padding(.bottom,12)
                    ScrollView {
                        AuthorRows(authors:all.filter { $0.matches(query) },library:library) { id in
                            let nextClose = SoftPanelCloseRequest()
                            nextClose.begin { withAnimation(motion) { selected = nil } }
                            childClose = nextClose
                            withAnimation(motion) { selected = id }
                        }
                        if all.isEmpty { ContentUnavailableView("还没有作者在这里",systemImage:"person.2",description:Text("可以在发现页认识作者，关注喜欢的创作。")) }
                        else if !query.isEmpty && !all.contains(where: { $0.matches(query) }) { Text("没有找到相关作者").foregroundStyle(Theme.secondary).padding(.vertical,30) }
                        Text("当前关系与数量来自本机体验身份。")
                            .font(.system(size:10)).foregroundStyle(Theme.secondary).padding(.vertical,20)
                        if let error = library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
                    }.padding(.horizontal,22).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                }.transition(.opacity)
            }
        }.softPanelPageSurface(opaque:true)
            .foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .onAppear { close?.beforeClose = { childClose.beforeClose?() ?? true } }
            .onDisappear { close?.beforeClose = nil }
    }
}

struct AuthorProfilePanel: View {
    let authorID: String
    let library: CharacterLibrary
    let store: CompanionStore
    let portraits: CharacterPortraitStore
    var onOpenCharacter: (String,Bool) -> Void
    private enum Page { case edit, followers, character(String) }
    @State private var page: Page?
    @State private var childClose = SoftPanelCloseRequest()
    @Environment(\.softPanelCloseRequest) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motion: Animation { .easeInOut(duration:reduceMotion ? 0.1 : 0.25) }
    private func open(_ page: Page) {
        let nextClose = SoftPanelCloseRequest()
        nextClose.begin { withAnimation(motion) { self.page = nil } }
        childClose = nextClose
        withAnimation(motion) { self.page = page }
    }
    var body: some View {
        ZStack {
            if let page {
                child(page).environment(\.softPanelCloseRequest,childClose)
                    .environment(\.softPanelDismiss,{ childClose.request() }).transition(.opacity)
            } else if let author = library.author(authorID) { profile(author).transition(.opacity) }
            else {
                VStack(spacing:0) {
                    PanelPageHeader("作者主页",backID:"closeAuthorProfile")
                    ContentUnavailableView("作者暂不可用",systemImage:"person.crop.circle.badge.questionmark")
                }.transition(.opacity)
            }
        }.softPanelPageSurface(opaque:true)
            .foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .onAppear { close?.beforeClose = { childClose.beforeClose?() ?? true } }
            .onDisappear { close?.beforeClose = nil }
    }
    @ViewBuilder private func child(_ page: Page) -> some View {
        switch page {
        case .edit:
            if let author = library.author(authorID) { AuthorEditorView(library:library,draft:author) }
        case .followers:
            AnyView(AuthorDirectoryPanel(kind:.followers(authorID),library:library,store:store,portraits:portraits,onOpenCharacter:onOpenCharacter))
        case .character(let id):
            if let model = library.model(id) {
                AnyView(CharacterDetailsPanel(model:model,store:store,library:library,portraits:portraits,
                    onChat:{ onOpenCharacter(id,false) },onCustomize:{ onOpenCharacter(id,true) },
                    onOpenCharacter:onOpenCharacter,allowsAuthorNavigation:false))
            }
        }
    }
    private func profile(_ author: AuthorProfile) -> some View {
        let works = library.publicWorks(by:authorID)
        return VStack(spacing:0) {
            PanelPageHeader("作者主页",backID:"closeAuthorProfile")
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    ProfileIdentityHeader(name:author.name,
                        subtitle:author.handle + (author.isBuiltin ? L10n.text(" · 内置作者") : ""),nameID:"authorProfileName") {
                        AuthorAvatar(author:author,size:52)
                    } accessory: {
                        if library.currentAuthor?.id == authorID {
                            Button { open(.edit) } label: { ProfileRelationshipLabel(title:"编辑资料") }
                                .buttonStyle(.plain).accessibilityIdentifier("editAuthorProfile")
                        } else {
                            AuthorFollowButton(author:author,library:library)
                        }
                    }
                    Text(author.bio.isEmpty ? "还没有写下介绍，先看看 TA 的角色吧。" : author.bio)
                        .font(.system(size:14)).lineSpacing(5).foregroundStyle(Theme.secondary)
                    HStack(spacing:28) {
                        Label("\(works.count) 个公开角色",systemImage:"sparkles").font(.system(size:13))
                        Button { open(.followers) } label: {
                            Text("\(library.followers(of:authorID).count) 位关注者").font(.system(size:13)).frame(minHeight:44)
                        }.buttonStyle(.plain).accessibilityIdentifier("authorFollowersButton")
                    }.foregroundStyle(Theme.peach)
                    VStack(alignment:.leading,spacing:4) {
                        Text("TA 创作的角色").font(.system(size:16,weight:.semibold))
                        Text("订阅角色，开始你们自己的故事。").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    }
                    if works.isEmpty {
                        Text(library.currentAuthor?.id == authorID ? "你还没有公开作品。私有角色保留在「我的 → 角色」里。" : "作者暂时没有公开角色，可以先关注，等下一次相遇。")
                            .font(.subheadline).foregroundStyle(Theme.secondary).padding(.vertical,12)
                    }
                    LazyVStack(spacing:10) {
                        ForEach(works) { model in
                            let profile = library.publishedProfile(model.id) ?? model.collection.initialProfile()
                            Button { open(.character(model.id)) } label: {
                                HStack(spacing:12) {
                                    CharacterAvatar(model:model,profile:profile,portraits:portraits,size:46,floatingEnabled:false)
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(profile.name).font(.system(size:14,weight:.medium))
                                        Text(profile.background).font(.system(size:11)).foregroundStyle(Theme.secondary).lineLimit(2)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Theme.secondary)
                                }.padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:18)).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("authorWork-"+model.id)
                        }
                    }
                    Text("当前为本机作品与关系预览，尚未同步到网络。")
                        .font(.system(size:10)).foregroundStyle(Theme.secondary)
                    if let error = library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
                }.padding(.horizontal,22).padding(.bottom,22)
            }.scrollIndicators(.hidden).accessibilityIdentifier("authorProfileScroll")
        }
    }
}

struct AuthorEditorView: View {
    let library: CharacterLibrary
    @State var draft: AuthorProfile
    @State private var validation: String?
    @Environment(\.softPanelCloseRequest) private var close
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("编辑作者资料",backID:"closeAuthorEditor")
            Form {
                Section("作者头像") {
                    HStack { Spacer(); AuthorAvatar(author:draft,size:76); Spacer() }.padding(.vertical,8)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6),spacing:6) {
                        ForEach(AuthorProfile.avatarChoices,id:\.self) { value in
                            var preview = draft; let _ = preview.avatar = value
                            Button { draft.avatar = value } label: {
                                AuthorAvatar(author:preview,size:38).padding(3)
                                    .overlay(Circle().stroke(draft.avatar == value ? Theme.accent : .clear,lineWidth:1))
                            }.buttonStyle(.plain).accessibilityLabel(L10n.text("作者头像 ") + value).accessibilityIdentifier("authorAvatar-"+value)
                        }
                    }
                }.listRowBackground(Theme.surface)
                Section("公开资料") {
                    TextField("作者名字",text:$draft.name).accessibilityIdentifier("authorNameInput")
                        .onChange(of:draft.name) { _, value in if value.count > 24 { draft.name = String(value.prefix(24)) } }
                    TextField("介绍你的创作",text:$draft.bio,axis:.vertical).lineLimit(3...6).accessibilityIdentifier("authorBioInput")
                        .onChange(of:draft.bio) { _, value in if value.count > 160 { draft.bio = String(value.prefix(160)) } }
                    Text("名字最多 24 字，介绍最多 160 字。返回时保存，所有作品同步显示这份作者资料。")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }.listRowBackground(Theme.surface)
                if let validation { Section { Text(LocalizedStringKey(validation)).font(.caption).foregroundStyle(Theme.peach) }.listRowBackground(Theme.surface) }
            }.scrollIndicators(.hidden).scrollContentBackground(.hidden)
                .contentMargins(.horizontal,22,for:.scrollContent)
                .contentMargins(.top,0,for:.scrollContent)
        }.softPanelPageSurface(opaque:true).foregroundStyle(Theme.ink).tint(Theme.accent)
            .softSheetSurface().onAppear { close?.beforeClose = save }
            .onDisappear { close?.beforeClose = nil }
    }
    private func save() -> Bool {
        guard library.updateAuthor(draft) else { validation = library.error; return false }
        return true
    }
}

struct CharacterSourceCreditsView: View {
    let model: ModelDescriptor
    private var credits: String {
        guard let url = Bundle.main.url(forResource:"CharacterSourceCredits",withExtension:"json"),
              let data = try? Data(contentsOf:url), let values = try? JSONDecoder().decode([String:String].self,from:data) else { return "素材署名暂不可用。" }
        return values[model.runtimeID] ?? "素材署名暂不可用。"
    }
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("模型素材与署名",backID:"closeCharacterCredits")
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("角色作者负责角色的设定与整理。以下是这个角色使用的 3D 模型、动作等素材原始署名。")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    Text(credits).font(.caption).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                }.padding(.horizontal,22).padding(.bottom,22)
            }.scrollIndicators(.hidden)
        }.softPanelPageSurface(opaque:true).foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
    }
}
