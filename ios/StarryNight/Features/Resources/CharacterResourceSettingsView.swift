import SwiftUI

/// Downloaded releases are durable resources, separate from regenerable voice
/// and thumbnail caches. Deleting them never mutates account or conversation data.
struct CharacterResourceSettingsView:View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var usage:[CharacterDownloadStore.Usage]=[]
    @State private var scanning=false
    @State private var removing:String?
    @State private var confirmation:ModelDescriptor?
    @State private var message:String?
    @Environment(\.scenePhase) private var scenePhase
    private var assets:CharacterAssetLibrary {coordinator.assets}
    private var downloadable:[ModelDescriptor] {
        Dictionary(ModelDescriptor.all.filter {assets.requiresDownload($0.runtimeID)}.map {($0.runtimeID,$0)},uniquingKeysWith:{a,_ in a}).values.sorted {$0.name<$1.name}
    }
    private var visible:[ModelDescriptor] {
        downloadable.filter {role in
            let bytes=usage.first {$0.id==role.runtimeID}?.bytes ?? 0
            if case .downloading=assets.phase(role.runtimeID){return true}
            return bytes>0
        }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    VStack(alignment:.leading,spacing:7) {
                        Text("已下载角色资源").font(.system(size:13)).foregroundStyle(Theme.secondary)
                        Text(CacheSize.text(usage.reduce(0){$0+$1.bytes})).font(.system(size:30,weight:.medium,design:.rounded)).monospacedDigit()
                            .accessibilityIdentifier("characterResourceTotal")
                    }
                    Spacer()
                    Button {Task {await refresh()}} label: {
                        Image(systemName:"arrow.clockwise").font(.system(size:14)).frame(width:42,height:42).background(Theme.surface,in:Circle())
                    }.buttonStyle(.plain).disabled(scanning || removing != nil).accessibilityLabel("重新计算角色资源")
                }
                Text("按角色管理模型、背景、音乐和配套资源。删除后仍保留聊天、记忆与订阅，下次相处时可重新下载。")
                    .font(.system(size:12)).lineSpacing(4).foregroundStyle(Theme.secondary)
                if scanning && usage.isEmpty {ProgressView().frame(maxWidth:.infinity).padding(30)}
                else if visible.isEmpty {
                    VStack(spacing:12) {
                        Image(systemName:"square.stack.3d.up").font(.system(size:25,weight:.light)).foregroundStyle(Theme.accent.opacity(0.7))
                        Text("还没有下载的角色").font(.system(size:14,weight:.medium))
                        Text("在发现页把喜欢的角色带到身边后，\n可以在这里管理她的资源。")
                            .font(.system(size:12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(4)
                    }.frame(maxWidth:.infinity).padding(.vertical,32).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                        .accessibilityIdentifier("characterResourcesEmpty")
                } else {
                    VStack(spacing:0) {
                        ForEach(visible) {role in
                            row(role)
                            if role.id != visible.last?.id {Rectangle().fill(Theme.line.opacity(0.35)).frame(height:0.5).padding(.leading,66)}
                        }
                    }.padding(.horizontal,14).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                }
                if let message {Text(LocalizedStringKey(message)).font(.system(size:12)).foregroundStyle(Theme.peach).lineSpacing(4).accessibilityIdentifier("characterResourceResult")}
                let bundled=ModelDescriptor.all.filter {!assets.requiresDownload($0.runtimeID)}.count
                Label("\(bundled) 个角色随 App 内置，由 App 更新管理，不占上述下载空间。",systemImage:"shippingbox")
                    .font(.system(size:11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }.padding(22)
        }.scrollIndicators(.hidden).background(Theme.background).foregroundStyle(Theme.ink).tint(Theme.accent)
            .navigationTitle("角色资源").navigationBarTitleDisplayMode(.inline)
            .task {await refresh()}
            .onChange(of:scenePhase) {_,phase in if phase == .active {Task {await refresh()}}}
            .onChange(of:assets.states) {_,_ in Task {await refresh()}}
            .alert("删除本地角色资源？",isPresented:Binding(get:{confirmation != nil},set:{if !$0{confirmation=nil}})) {
                Button("取消",role:.cancel){confirmation=nil}
                Button("删除资源",role:.destructive) {
                    guard let role=confirmation else{return};confirmation=nil
                    Task {await remove(role)}
                }
            } message: {
                Text("只移除“\(confirmation?.name ?? "")”的本机下载包。聊天、记忆和订阅会保留，再次进入会话需要重新下载。")
            }
    }
    private func row(_ role:ModelDescriptor)->some View {
        let info=usage.first {$0.id==role.runtimeID}
        return HStack(spacing:12) {
            CharacterAvatar(model:role,profile:coordinator.profile(for:role),portraits:coordinator.portraits,size:40,floatingEnabled:false)
            VStack(alignment:.leading,spacing:5) {
                HStack {Text(role.name).font(.system(size:14,weight:.medium));Spacer();Text(CacheSize.text(info?.bytes ?? 0)).font(.system(size:11)).monospacedDigit().foregroundStyle(Theme.secondary)}
                if case .downloading(let progress,let label)=assets.phase(role.runtimeID) {
                    Text(label+" · \(Int(progress*100))%").font(.system(size:10)).foregroundStyle(Theme.accent)
                    ProgressView(value:progress).tint(Theme.accent)
                } else {Text(info?.installed==true ? "已就绪 · 含全部本地版本" : "未完成的下载资源").font(.system(size:10)).foregroundStyle(Theme.secondary)}
            }
            Button {confirmation=role} label: {
                if removing==role.runtimeID {ProgressView().controlSize(.small).frame(width:40,height:40)}
                else {Image(systemName:"trash").font(.system(size:13)).foregroundStyle(Color.red.opacity(0.8)).frame(width:40,height:40).contentShape(Rectangle())}
            }.buttonStyle(.plain).disabled(removing != nil).accessibilityIdentifier("removeCharacterResource-"+role.runtimeID).accessibilityLabel("删除“"+role.name+"”的本地资源")
        }.padding(.vertical,16).accessibilityElement(children:.contain)
    }
    private func refresh() async {
        guard !scanning else{return};scanning=true;defer {scanning=false}
        do {usage=try await CharacterDownloadStore.shared.usage(characterIDs:Set(downloadable.map(\.runtimeID)),accountID:coordinator.library.accountID,platform:CharacterAssetLibrary.platform)}
        catch {message="部分角色资源暂时无法读取，请稍后重新计算。"}
    }
    private func remove(_ role:ModelDescriptor) async {
        guard removing==nil else{return};removing=role.runtimeID;message=nil
        do {try await coordinator.removeDownloadedCharacter(role.runtimeID);message="已移除“\(role.name)”的本地资源，聊天与记忆已保留。"}
        catch {message=error.localizedDescription}
        removing=nil;await refresh()
    }
}
