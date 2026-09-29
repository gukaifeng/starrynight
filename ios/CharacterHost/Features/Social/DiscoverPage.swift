import SwiftUI

struct DiscoverPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var filter = "全部"
    @State private var search = ""
    @State private var details:ModelDescriptor?
    @State private var showingDetails = false
    @State private var pendingEntry:(String,Bool)?

    private var models:[ModelDescriptor] {
        (filter == "关注作者" ? coordinator.library.followedAuthorWorks : coordinator.library.discover).filter { model in
            (filter != "已订阅" || coordinator.library.subscriptions.contains(model.id)) &&
            (filter != "原创" || coordinator.library.creation(model.id) != nil) &&
            (!["日常","校园","幻想"].contains(filter) || CompanionStory.available(for:model).contains(where:{ $0.category == filter })) &&
            CharacterSearch.matches(search,model:model,profile:coordinator.profile(for:model),authorName:coordinator.library.author(for:model.id)?.name ?? "")
        }
    }
    private func openPending() {
        guard let entry = pendingEntry else { return }; pendingEntry = nil
        coordinator.openCharacter(entry.0,customize:entry.1)
    }
    private func openCharacter(_ id:String,_ customize:Bool) {
        pendingEntry = (id,customize); showingDetails = false
    }
    var body:some View {
        VStack(spacing:0) {
            NightHeader(title:"发现",subtitle:"找一个，想聊下去的人")
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").font(.system(size:13)).foregroundStyle(Theme.secondary)
                TextField("搜角色、作者或性格",text:$search).font(.system(size:13))
                    .submitLabel(.search).accessibilityIdentifier("discoverSearch")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(Theme.secondary) }
                        .accessibilityLabel("清除搜索").accessibilityIdentifier("clearDiscoverSearch")
                }
                Text("\(models.count) 位").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    .fixedSize().accessibilityIdentifier("discoverCount")
            }.padding(.horizontal,12).frame(height:36).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
                .padding(.horizontal,20).padding(.bottom,12)
            HStack(spacing:4) {
                ScrollView(.horizontal) {
                HStack(spacing:4) {
                ForEach(["全部","日常","校园","幻想","已订阅","关注作者","原创"],id:\.self) { option in
                    Button { filter = option } label: {
                        Text(option).font(.system(size:13,weight:filter == option ? .semibold : .regular))
                            .padding(.horizontal,12).frame(height:32)
                            .foregroundStyle(filter == option ? Theme.accent : Theme.secondary)
                            .background(filter == option ? Theme.card : .clear,in:Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("discover-"+option)
                }
                }
                }.scrollIndicators(.hidden)
            }.padding(.horizontal,20).padding(.bottom,10)
            ScrollView {
                LazyVGrid(columns:[GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12)],spacing:14) {
                    ForEach(models) { model in card(model) }
                }
                if models.isEmpty {
                    VStack(spacing:10) {
                        Image(systemName:"magnifyingglass").font(.title2)
                        Text(search.isEmpty ? (filter == "关注作者" ? "先关注喜欢的作者，TA 的公开角色会出现在这里。" : "还没有角色，试试其他分类。") : "没有找到，换个关键词试试。")
                            .font(.subheadline)
                    }.foregroundStyle(Theme.secondary).frame(maxWidth:.infinity).padding(.vertical,50)
                }
                Text("本机角色展厅 · 公开作品尚未同步到网络")
                    .font(.system(size:10)).foregroundStyle(Theme.secondary).padding(.vertical,20)
                if let error = coordinator.library.error { Text(error).font(.caption).foregroundStyle(Theme.peach) }
            }.padding(.horizontal,20).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }.accessibilityElement(children:.contain).accessibilityIdentifier("discoverPage")
            .accessibilityHidden(showingDetails)
            .softSheet(isPresented:$showingDetails,height:620,onDismiss:openPending) {
                if let model = details {
                    CharacterDetailsPanel(model:model,store:coordinator.companionStore,library:coordinator.library,
                        portraits:coordinator.portraits,onChat:{ openCharacter(model.id,false) },
                        onCustomize:{ openCharacter(model.id,true) },onOpenCharacter:openCharacter)
                }
            }
    }
    private func card(_ model:ModelDescriptor) -> some View {
        let profile = coordinator.profile(for:model)
        return Button {
            details = model; showingDetails = true
        } label: {
            VStack(alignment:.leading,spacing:0) {
                CharacterCover(model:model).aspectRatio(4.0/3.0,contentMode:.fit)
                    .overlay(alignment:.bottom) {
                        LinearGradient(colors:[.clear,Theme.surface.opacity(0.24)],startPoint:.top,endPoint:.bottom)
                            .frame(height:22)
                    }
                VStack(alignment:.leading,spacing:5) {
                    Text(profile.name).font(.system(size:14,weight:.semibold,design:.rounded))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Text(model.display.invitation).font(.system(size:11)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    HStack(spacing:5) {
                        Text(coordinator.library.author(for:model.id)?.name ?? "作者暂不可用").lineLimit(1)
                        Spacer(minLength:0)
                        Text(CompanionStory.available(for:model).first?.category ?? "")
                            .foregroundStyle(Theme.peach.opacity(0.75)).fixedSize()
                    }.font(.system(size:9)).foregroundStyle(Theme.secondary.opacity(0.8)).padding(.top,1)
                }.padding(.horizontal,11).padding(.top,10).padding(.bottom,11)
            }.frame(maxWidth:.infinity,alignment:.leading)
                .background(Theme.surface.opacity(Theme.panelOpacity))
                .clipShape(RoundedRectangle(cornerRadius:17,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:17,style:.continuous).stroke(Theme.line.opacity(0.35),lineWidth:0.5))
                .contentShape(RoundedRectangle(cornerRadius:17,style:.continuous))
        }.buttonStyle(.plain).accessibilityIdentifier("discover-open-"+model.id)
            .accessibilityLabel("查看"+profile.name+"的资料")
    }
}
