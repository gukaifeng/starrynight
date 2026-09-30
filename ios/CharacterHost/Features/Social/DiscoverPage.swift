import SwiftUI

struct DiscoverPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var query = MarketQuery()
    @State private var featuredIndex = 0
    @State private var details:ModelDescriptor?
    @State private var showingDetails = false
    @State private var pendingEntry:(String,Bool)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var catalog:[CharacterMarketItem] { CharacterMarketplace.localCatalog(coordinator.library) }
    private var items:[CharacterMarketItem] {
        CharacterMarketplace.results(catalog,query:query,subscriptions:Set(coordinator.library.subscriptions),
                                     followedAuthors:Set(coordinator.library.followedAuthors))
    }
    private var featured:[CharacterMarketItem] {
        catalog.filter(\.featured).sorted { $0.rank < $1.rank }
    }
    private var showsFeatured:Bool {
        query.shelf == .recommended && query.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty &&
            !query.hasFilters && !featured.isEmpty
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
            NightHeader(title:"发现",subtitle:"探索角色，找到想聊下去的伙伴")
            CatalogSearchField(placeholder:"搜角色、剧情或英语陪练",text:$query.text,
                identifier:"discoverSearch",clearIdentifier:"clearDiscoverSearch")
                .padding(.horizontal,24).padding(.bottom,10)
            shelfBar.padding(.horizontal,24).padding(.bottom,5)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        Color.clear.frame(height:0).id("marketTop")
                        if showsFeatured { featuredShelf }
                        categoryBar
                        resultHeading
                        if items.isEmpty { emptyCatalog }
                        else {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:14) {
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
                        if let error = coordinator.library.error { Text(error).font(.caption).foregroundStyle(Theme.peach) }
                    }.padding(.horizontal,24)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                    .onChange(of:query) { _,_ in proxy.scrollTo("marketTop",anchor:.top) }
            }
        }.foregroundStyle(Theme.ink)
            .accessibilityElement(children:.contain).accessibilityIdentifier("discoverPage")
            .accessibilityHidden(showingDetails)
            .onChange(of:coordinator.library.accountID) { _,_ in
                query = MarketQuery(); showingDetails = false; details = nil; pendingEntry = nil; featuredIndex = 0
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
        HStack(spacing:22) {
            ForEach(MarketShelf.allCases) { shelf in
                Button {
                    query.shelf = shelf
                } label: {
                    Text(shelf.rawValue).font(.system(size:16,weight:query.shelf == shelf ? .semibold : .regular))
                        .foregroundStyle(query.shelf == shelf ? Theme.ink : Theme.secondary)
                        .frame(height:40)
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
    private var featuredShelf:some View {
        VStack(spacing:8) {
            TabView(selection:$featuredIndex) {
                ForEach(Array(featured.enumerated()),id:\.element.id) { index,item in
                    Button { show(item) } label: {
                        HStack(spacing:0) {
                            VStack(alignment:.leading,spacing:8) {
                                Label("星夜精选",systemImage:"sparkle").font(.system(size:10,weight:.medium))
                                    .tracking(1).foregroundStyle(Theme.peach)
                                Text(item.profile.name).font(.system(size:23,weight:.medium,design:.serif)).lineLimit(1)
                                Text(CharacterPublicProfile.find(item.model.runtimeID)?.invitation ?? item.model.display.invitation).font(.system(size:11)).lineSpacing(3)
                                    .foregroundStyle(Theme.secondary).lineLimit(2)
                                Label("认识一下",systemImage:"arrow.up.right").font(.system(size:10,weight:.medium))
                                    .foregroundStyle(Theme.accent).padding(.top,3)
                            }.padding(.leading,18).padding(.vertical,15).frame(maxWidth:.infinity,alignment:.leading)
                            CharacterCover(model:item.model,focalCrop:true)
                                .mask(LinearGradient(colors:[.clear,.white,.white],startPoint:.leading,endPoint:.trailing))
                                .frame(maxWidth:.infinity)
                        }.frame(height:150).background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
                            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Theme.peach.opacity(0.16),lineWidth:0.5))
                    }.buttonStyle(.plain).tag(index)
                        .accessibilityLabel("精选，"+item.profile.name+"，查看资料")
                        .accessibilityIdentifier("marketFeatured-"+item.id)
                }
            }.tabViewStyle(.page(indexDisplayMode:.never)).frame(height:150)
                .accessibilityIdentifier("marketFeaturedShelf")
            if featured.count > 1 {
                HStack(spacing:5) {
                    ForEach(featured.indices,id:\.self) { index in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { featuredIndex = index }
                        } label: {
                            Capsule().fill(Theme.accent.opacity(featuredIndex == index ? 0.8 : 0.22))
                                .frame(width:featuredIndex == index ? 16 : 5,height:3).padding(.vertical,5)
                        }.buttonStyle(.plain).accessibilityLabel("精选第\(index+1)位")
                    }
                }
            }
        }
    }
    private var categoryBar:some View {
        ScrollView(.horizontal) {
            HStack(spacing:8) {
                ForEach(CharacterMarketplace.categories(catalog),id:\.self) { category in
                    Button { query.category = category } label: {
                        Text(category).font(.system(size:12,weight:query.category == category ? .medium : .regular))
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
                    ForEach(MarketSort.allCases) { option in Text(option.rawValue).tag(option) }
                }
            } label: {
                HStack(spacing:5) {
                    Text(query.sort.rawValue)
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
                 "公开的角色会出现在这里。\n也可以先到精选，认识星夜的伙伴。" : "试试角色名、作者名，或放宽筛选条件。")
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
                CharacterCover(model:item.model).aspectRatio(4.0/3.0,contentMode:.fit)
                    .overlay(alignment:.topLeading) {
                        Text(item.categories.first ?? "3D 角色").font(.system(size:9,weight:.medium))
                            .padding(.horizontal,7).padding(.vertical,4)
                            .background(Theme.background.opacity(0.7),in:Capsule()).padding(8)
                    }
                VStack(alignment:.leading,spacing:5) {
                    Text(item.profile.name).font(.system(size:14,weight:.semibold,design:.rounded)).lineLimit(1)
                    Text(CharacterPublicProfile.find(item.model.runtimeID)?.invitation ?? item.model.display.invitation).font(.system(size:11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    HStack(spacing:4) {
                        Image(systemName:item.isCreatorWork ? "person.crop.circle" : "sparkle").font(.system(size:9))
                        Text(item.authorName).lineLimit(1)
                        Spacer(minLength:0)
                        Text("3D").font(.system(size:9,weight:.medium,design:.rounded)).foregroundStyle(Theme.peach)
                    }.font(.system(size:10)).foregroundStyle(Theme.secondary.opacity(0.8)).padding(.top,2)
                }.padding(11).frame(maxWidth:.infinity,alignment:.leading)
            }.background(Theme.surface.opacity(Theme.panelOpacity))
                .clipShape(RoundedRectangle(cornerRadius:17,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:17).strokeBorder(Theme.line.opacity(0.28),lineWidth:0.5))
                .contentShape(RoundedRectangle(cornerRadius:17))
        }.buttonStyle(.plain).accessibilityIdentifier("discover-open-"+item.id)
            .accessibilityLabel("查看"+item.profile.name+"的资料，"+item.categories.joined(separator:"、")+"，作者"+item.authorName)
    }
}
