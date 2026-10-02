import SwiftUI

struct DiscoverPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var query = MarketQuery()
    @State private var details:ModelDescriptor?
    @State private var showingDetails = false
    @State private var pendingEntry:(String,Bool)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var catalog:[CharacterMarketItem] { CharacterMarketplace.localCatalog(coordinator.library) }
    private var items:[CharacterMarketItem] {
        CharacterMarketplace.results(catalog,query:query,subscriptions:Set(coordinator.library.subscriptions),
                                     followedAuthors:Set(coordinator.library.followedAuthors))
    }
    private func openPending() {
        guard let entry = pendingEntry else { return }; pendingEntry = nil
        coordinator.openCharacter(entry.0,customize:entry.1)
    }
    private func openCharacter(_ id:String,_ customize:Bool) {
        pendingEntry = (id,customize); showingDetails = false
    }
    private func show(_ item:CharacterMarketItem) { details = item.model; showingDetails = true }
    var body:some View {
        VStack(spacing:0) {
            HStack { Text("发现").font(.system(size:25,weight:.semibold,design:.rounded)); Spacer(); Text("遇见心动的故事").font(.system(size:11)).foregroundStyle(Theme.secondary) }.padding(.horizontal,18).padding(.top,14).padding(.bottom,12)
            CatalogSearchField(placeholder:"搜角色、剧情或英语陪练",text:$query.text,
                identifier:"discoverSearch",clearIdentifier:"clearDiscoverSearch")
                .padding(.horizontal,18).padding(.bottom,5)
            shelfBar.padding(.horizontal,18).padding(.bottom,5)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        Color.clear.frame(height:0).id("marketTop")
                        categoryBar
                        resultHeading
                        if items.isEmpty { emptyCatalog }
                        else {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:108),spacing:8)],spacing:10) {
                                ForEach(items) { item in card(item) }
                            }.accessibilityIdentifier("marketCatalogGrid")
                        }
                        Button { coordinator.navigate(.create) } label: {
                            HStack(spacing:10) {
                                Image(systemName:"sparkles").font(.system(size:17,weight:.light)).foregroundStyle(Theme.peach)
                                VStack(alignment:.leading,spacing:4) {
                                    Text("让你的想象，也成为伙伴").font(.system(size:13,weight:.medium))
                                    Text("创建角色，自用或分享你的作品").font(.system(size:11)).foregroundStyle(Theme.secondary)
                                }
                                Spacer(minLength:4)
                                Image(systemName:"arrow.up.right").font(.system(size:12)).foregroundStyle(Theme.secondary)
                            }.padding(.vertical,16).padding(.horizontal,14)
                                .background(Theme.surface.opacity(0.45),in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain).accessibilityIdentifier("marketCreateCharacter")
                            .padding(.top,4).padding(.bottom,20)
                        if let error = coordinator.library.error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Theme.peach) }
                    }.padding(.horizontal,18)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                    .onChange(of:query) { _,_ in proxy.scrollTo("marketTop",anchor:.top) }
            }
        }.foregroundStyle(Theme.ink)
            .accessibilityElement(children:.contain).accessibilityIdentifier("discoverPage")
            .accessibilityHidden(showingDetails)
            .onChange(of:coordinator.library.accountID) { _,_ in
                query = MarketQuery(); showingDetails = false; details = nil; pendingEntry = nil
            }
            .softSheet(isPresented:$showingDetails,height:620,onDismiss:openPending) {
                if let model = details {
                    CharacterDetailsPanel(model:model,store:coordinator.companionStore,library:coordinator.library,
                        portraits:coordinator.portraits,onChat:{ openCharacter(model.id,false) },
                        onCustomize:{ openCharacter(model.id,true) },onOpenCharacter:openCharacter)
                }
            }
    }
    private var shelfBar:some View {
        HStack(spacing:20) {
            ForEach(MarketShelf.allCases.filter { $0 != .recommended }) { shelf in
                Button {
                    query.shelf = shelf
                } label: {
                    Text(LocalizedStringKey(shelf.rawValue)).font(.system(size:16,weight:query.shelf == shelf ? .semibold : .regular))
                        .foregroundStyle(query.shelf == shelf ? Theme.ink : Theme.secondary)
                        .frame(height:36)
                        .overlay(alignment:.bottom) {
                            Capsule().fill(Theme.gradient).frame(width:18,height:2)
                                .opacity(query.shelf == shelf ? 1 : 0)
                        }
                }.buttonStyle(.plain).accessibilityIdentifier("marketShelf-"+shelf.rawValue)
                    .accessibilityAddTraits(query.shelf == shelf ? .isSelected : [])
            }
            Spacer(minLength:0)
            Menu {
                Toggle("只看已订阅",isOn:$query.subscribedOnly).accessibilityIdentifier("marketSubscribedFilter")
                Toggle("只看关注的作者",isOn:$query.followedAuthorsOnly).accessibilityIdentifier("marketAuthorFilter")
                if query.hasFilters {
                    Button("重置筛选") { query.category = "全部"; query.subscribedOnly = false; query.followedAuthorsOnly = false }
                }
            } label: {
                Image(systemName:"line.3.horizontal.decrease").font(.system(size:16))
                    .foregroundStyle(query.hasFilters ? Theme.accent : Theme.secondary)
                    .frame(width:40,height:40)
                    .background(query.hasFilters ? Theme.card : .clear,in:Circle())
            }.accessibilityLabel("筛选角色").accessibilityIdentifier("marketFilterMenu")
        }
    }
    private var categoryBar:some View {
        ScrollView(.horizontal) {
            HStack(spacing:8) {
                ForEach(CharacterMarketplace.categories(catalog),id:\.self) { category in
                    Button { query.category = category } label: {
                        Text(LocalizedStringKey(category)).font(.system(size:12,weight:query.category == category ? .medium : .regular))
                            .padding(.horizontal,13).frame(height:30)
                            .foregroundStyle(query.category == category ? Theme.background : Theme.secondary)
                            .background(query.category == category ? Theme.accent : Theme.surface,in:Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("discover-"+category)
                        .accessibilityAddTraits(query.category == category ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden)
    }
    private var resultHeading:some View {
        HStack(alignment:.firstTextBaseline) {
            Text(query.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ?
                 (query.shelf == .creators ? "创作者作品" : "角色馆") : "搜索结果")
                .font(.system(size:16,weight:.semibold))
            Text("\(items.count) 位").font(.system(size:11)).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("discoverCount")
            Spacer()
            Menu {
                Picker("排序",selection:$query.sort) {
                    ForEach(MarketSort.allCases) { option in Text(LocalizedStringKey(option.rawValue)).tag(option) }
                }
            } label: {
                HStack(spacing:5) {
                    Text(LocalizedStringKey(query.sort.rawValue))
                    Image(systemName:"chevron.down").font(.system(size:8,weight:.medium))
                }.font(.system(size:11)).foregroundStyle(Theme.secondary).padding(.vertical,5)
            }.accessibilityIdentifier("marketSortMenu")
        }
    }
    private var emptyCatalog:some View {
        VStack(spacing:14) {
            Image(systemName:query.shelf == .creators && !query.hasFilters && query.text.isEmpty ? "sparkles" : "magnifyingglass")
                .font(.system(size:27,weight:.ultraLight)).foregroundStyle(Theme.accent)
            Text(query.shelf == .creators && !query.hasFilters && query.text.isEmpty ? "第一份作品，等你带来" : "还没有找到这样的伙伴")
                .font(.system(size:15,weight:.medium))
            Text(query.shelf == .creators && !query.hasFilters && query.text.isEmpty ?
                 "公开的角色会出现在这里。\n也可以到全部，认识星夜的伙伴。" : "试试角色名、作者名，或放宽筛选条件。")
                .font(.system(size:12)).lineSpacing(4).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            Button("看看全部角色") { query = MarketQuery(); query.shelf = .all }
                .font(.system(size:12,weight:.medium)).padding(.horizontal,16).frame(height:38)
                .background(Theme.card,in:Capsule()).accessibilityIdentifier("resetMarketQuery")
        }.frame(maxWidth:.infinity).padding(.vertical,28)
            .accessibilityElement(children:.contain).accessibilityIdentifier("marketEmptyState")
    }
    private func card(_ item:CharacterMarketItem) -> some View {
        Button { show(item) } label: {
            VStack(alignment:.leading,spacing:0) {
                CharacterCover(model:item.model).aspectRatio(0.94,contentMode:.fit)
                VStack(alignment:.leading,spacing:5) {
                    Text(item.profile.name).font(.system(size:13,weight:.semibold,design:.rounded)).lineLimit(1)
                    Text(CharacterPublicProfile.find(item.model.runtimeID)?.invitation ?? item.model.display.invitation).font(.system(size:10)).foregroundStyle(Theme.secondary).lineLimit(1)
                }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
            }.background(Theme.surface.opacity(Theme.panelOpacity))
                .clipShape(RoundedRectangle(cornerRadius:13,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Theme.line.opacity(0.28),lineWidth:0.5))
                .contentShape(RoundedRectangle(cornerRadius:13))
        }.buttonStyle(.plain).accessibilityIdentifier("discover-open-"+item.id)
            .accessibilityLabel("查看"+item.profile.name+"的资料")
    }
}
