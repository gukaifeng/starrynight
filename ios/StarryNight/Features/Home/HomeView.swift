import SwiftUI

struct HomeView: View {
    @Bindable var coordinator: ViewerCoordinator
    @State private var showingAccount = false
    @State private var selectedModelID = ModelDescriptor.all[0].id
    @State private var visiblePage = 0
    @State private var pageDrag: CGFloat = 0
    @State private var horizontalDrag: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var motion: Animation { reduceMotion ? .easeInOut(duration:0.18) : .spring(response:0.46,dampingFraction:0.92) }
    private var greeting: String {
        switch Calendar.current.component(.hour,from:Date()) {
        case 5..<11: "早上好，慢慢开启今天。"
        case 11..<18: "忙了一会儿，来歇歇吧。"
        default: "夜色温柔，留一点时间给自己。"
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let short = geometry.size.height < 500
            VStack(alignment:.leading,spacing:short ? 6 : 20) {
                HStack(alignment:.center) {
                    BrandSignature(size:short ? 26 : 32)
                    if short {
                        Spacer()
                        Text("今天，想和谁聊聊？").font(.system(size:19,weight:.medium,design:.rounded))
                            .accessibilityIdentifier("homeHeadline")
                    }
                    Spacer()
                    accountButton
                }.frame(height:44)
                if !short {
                    VStack(alignment:.leading,spacing:7) {
                        Text(LocalizedStringKey(greeting)).font(.system(size:12)).foregroundStyle(Theme.secondary)
                        Text("今天，想和谁聊聊？").font(.system(size:geometry.size.width>600 ? 30 : 25,weight:.medium,design:.rounded))
                            .lineLimit(1).minimumScaleFactor(0.8).accessibilityIdentifier("homeHeadline")
                    }.padding(.top,4)
                }
                GeometryReader { area in
                    let layout = CharacterHomeLayout(size:CGSize(width:area.size.width,height:max(1,area.size.height-42)),
                        count:ModelDescriptor.all.count,largeText:dynamicType.isAccessibilitySize)
                    VStack(spacing:10) {
                        galleryHeader(layout)
                        gallery(layout).frame(height:layout.gridHeight)
                    }
                    .onChange(of:layout.capacity) { _,_ in restorePage(layout) }
                    .onChange(of:coordinator.page) { _, page in
                        if page == .home { selectedModelID = coordinator.selectedModel.id;restorePage(layout) }
                    }
                }
            }
            .padding(.horizontal,geometry.size.width>600 ? 32 : 20)
            .padding(.top,short ? 4 : 16).padding(.bottom,short ? 4 : 20)
            .frame(maxWidth:1240,maxHeight:.infinity,alignment:.top).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
            .background(LinearGradient(colors:[Theme.card.opacity(0.65),Theme.background,Theme.peach.opacity(0.13)],
                startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea())
            .allowsHitTesting(coordinator.page == .home).accessibilityHidden(coordinator.page != .home)
        }.foregroundStyle(Theme.ink).tint(Theme.accent)
            .softSheet(isPresented:$showingAccount) {
                AccountCenterView(account:coordinator.account,onSignOut:{ showingAccount = false;coordinator.account.signOut() })
            }
            .overlay(alignment:.bottom) {
                if coordinator.showsLoadingIndicator {
                    LoadingView(failed:coordinator.page == .error,errorMessage:coordinator.errorMessage,onCancel:coordinator.closeViewer)
                        .frame(maxWidth:420).padding(.horizontal,30).padding(.bottom,62)
                        .transition(.opacity.combined(with:.offset(y:reduceMotion ? 0 : 8)))
                }
            }
            .animation(.easeInOut(duration:0.24),value:coordinator.showsLoadingIndicator)
            .preferredColorScheme(.dark)
    }
    private func restorePage(_ layout:CharacterHomeLayout) {
        let index = ModelDescriptor.all.firstIndex { $0.id == selectedModelID } ?? 0
        pageDrag=0;horizontalDrag=nil
        visiblePage = layout.page(containing:index)
    }
    private func galleryHeader(_ layout:CharacterHomeLayout) -> some View {
        HStack(spacing:8) {
            Text("你的陪伴").font(.system(size:13,weight:.medium))
            Text("\(ModelDescriptor.all.count) 位").font(.system(size:11)).foregroundStyle(Theme.secondary)
            Spacer()
            if layout.pages>1 {
                HStack(spacing:0) {
                    ForEach(0..<layout.pages,id:\.self) { page in
                        Button { withAnimation(motion) { visiblePage = page } } label: {
                            Capsule().fill(visiblePage == page ? Theme.ink.opacity(0.7) : Theme.secondary.opacity(0.25))
                                .frame(width:visiblePage == page ? 18 : 5,height:4).frame(width:30,height:32)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("第\(page+1)页角色")
                            .accessibilityValue(visiblePage == page ? "已选中" : "未选中")
                            .accessibilityIdentifier("homePage-\(page)")
                    }
                }.accessibilityElement(children:.contain).accessibilityIdentifier("homePageIndicators")
            }
        }.frame(height:32).accessibilityElement(children:.contain)
            .accessibilityIdentifier("homeGalleryHeader")
#if DEBUG
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? "columns=\(layout.columns);rows=\(layout.rows);capacity=\(layout.capacity);pages=\(layout.pages);page=\(visiblePage)" : "")
#endif
    }
    private func gallery(_ layout:CharacterHomeLayout) -> some View {
        GeometryReader { area in
            HStack(spacing:0) {
                    ForEach(0..<layout.pages,id:\.self) { page in
                        VStack(spacing:layout.gap) {
                            ForEach(0..<layout.rows,id:\.self) { row in
                                HStack(spacing:layout.gap) {
                                    ForEach(0..<layout.columns,id:\.self) { column in
                                        let index = page*layout.capacity+row*layout.columns+column
                                        if index<ModelDescriptor.all.count {
                                            let model = ModelDescriptor.all[index]
                                            let record = coordinator.companionStore.record(model.id)
                                            CharacterHomeCard(model:model,profile:record.profile,
                                                portrait:coordinator.portraits.image(model,profile:record.profile),size:layout.card,index:index,
                                                hasConversation:!record.messages.isEmpty,isActive:coordinator.page == .home && visiblePage == page) {
                                                    selectedModelID = model.id;coordinator.openCompanion(model)
                                                }
                                        } else { Color.clear.frame(width:layout.card.width,height:layout.card.height) }
                                    }
                                }
                            }
                        }.frame(width:area.size.width,height:layout.gridHeight,alignment:.top).id(page)
                            .accessibilityElement(children:.contain)
                            .accessibilityHidden(page != visiblePage)
                    }
            }
            .frame(width:area.size.width,alignment:.leading)
            .offset(x:-CGFloat(visiblePage)*area.size.width+pageDrag)
            .frame(width:area.size.width,height:layout.gridHeight,alignment:.leading)
            .clipped().contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance:12).onChanged { value in
                if horizontalDrag == nil { horizontalDrag = abs(value.translation.width)>abs(value.translation.height) }
                guard horizontalDrag == true, layout.pages>1, coordinator.page == .home else { return }
                let translation=value.translation.width
                let atEdge=(visiblePage==0 && translation>0) || (visiblePage==layout.pages-1 && translation<0)
                pageDrag=translation*(atEdge ? 0.18 : 1)
            }.onEnded { value in
                guard horizontalDrag == true else { horizontalDrag=nil;pageDrag=0;return }
                let target=layout.page(after:visiblePage,translation:value.translation.width,
                    predicted:value.predictedEndTranslation.width,width:area.size.width)
                withAnimation(motion) { visiblePage=target;pageDrag=0 }
                horizontalDrag=nil
                rememberPage(layout)
            })
            .accessibilityElement(children:.contain).accessibilityIdentifier("homeGallery")
            .onChange(of:visiblePage) { _,_ in rememberPage(layout) }

        }
    }
    private func rememberPage(_ layout:CharacterHomeLayout) {
        guard coordinator.page == .home else { return }
        let current=ModelDescriptor.all.firstIndex { $0.id == selectedModelID } ?? 0
        if layout.page(containing:current) != visiblePage {
            selectedModelID=ModelDescriptor.all[min(ModelDescriptor.all.count-1,visiblePage*layout.capacity)].id
        }
    }
    private var accountButton: some View {
        Button { showingAccount = true } label: {
            Image(systemName:"person.crop.circle").font(.system(size:18,weight:.regular))
                .frame(width:34,height:34).background(Theme.surface.opacity(0.55),in:Circle())
                .overlay(Circle().stroke(.white.opacity(0.75),lineWidth:0.5))
                .frame(width:44,height:44).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel("我的账号与关于星夜").accessibilityIdentifier("accountCenterButton")
#if DEBUG
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? coordinator.soundscape.accessibilityEvidence : "")
#endif
    }
}
