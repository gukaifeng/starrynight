import SwiftUI

// HOST-EMOTION-EXPERIMENT v3. Developer experiment, deliberately independent of
// XCP author selections and account/character customization records.
enum HostEmotionMotionPreference {
    static let key = "hostEmotionMotionEnabled.v1"
    static let notification = Notification.Name("HostEmotionMotionRequest.v1")
    static var enabled: Bool { UserDefaults.standard.object(forKey:key) as? Bool ?? true }
    static let speechKey="hostEmotionMotionSpeechLinked.v3"
    static var speechLinked:Bool {UserDefaults.standard.bool(forKey:speechKey)}
    static func request(_ kind:String,actor:String,gesture:String = "") {
        NotificationCenter.default.post(name:notification,object:nil,userInfo:["kind":kind,"actor":actor,"gesture":gesture])
    }
}

#if STARRY_TEST_TOOLS
struct HostGestureCatalog:Decodable {
    struct Group:Decodable,Identifiable {let id,label:String}
    struct Gesture:Decodable,Identifiable {let id,label,group:String;let duration:Double}
    let revision:Int
    let groups:[Group]
    let gestures:[Gesture]
    static let shared:Self? = {
        guard let url=Bundle.main.url(forResource:"HostEmotionGestures",withExtension:"json"),
              let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Self.self,from:data),
              value.revision==3 else {return nil}
        return value
    }()
}
struct HostEmotionMotionPanel: View {
    let model:ModelDescriptor
    let state:CharacterPerformanceState
    @AppStorage(HostEmotionMotionPreference.key) private var enabled=true
    @AppStorage(HostEmotionMotionPreference.speechKey) private var speechLinked=false
    @State private var group=""
    @State private var search=""
    @FocusState private var searching:Bool
    private var catalog:HostGestureCatalog? {HostGestureCatalog.shared}
    private var gestures:[HostGestureCatalog.Gesture] {
        (catalog?.gestures ?? []).filter{(group.isEmpty || $0.group==group) &&
            (search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search))}
    }
    var body:some View {
        VStack(spacing:0) {
        PanelPageHeader("动作实验 · "+model.name,backID:"closeHostEmotionMotion") {
            Button {HostEmotionMotionPreference.request("stop",actor:model.runtimeID)} label:{
                Text("结束预览").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.secondary).frame(minHeight:44)
            }.buttonStyle(.plain).accessibilityIdentifier("hostEmotionStop")
        }
        ScrollView {
            VStack(alignment:.leading,spacing:10) {
                Toggle(isOn:$enabled) {
                    VStack(alignment:.leading,spacing:3) {
                        Text("身体与表情组合").font(.system(size:13,weight:.medium))
                        Text("宿主附加层 · 不改原作动作、口型与物理")
                            .font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }
                }.toggleStyle(.switch).tint(Theme.accent)
                    .accessibilityIdentifier("hostEmotionMotionToggle")
                    .onChange(of:enabled) { _,_ in HostEmotionMotionPreference.request("configure",actor:model.runtimeID) }
                Toggle(isOn:$speechLinked) {
                    VStack(alignment:.leading,spacing:3) {
                        Text("随语音联动 · 实验").font(.system(size:13,weight:.medium))
                        Text("根据已有 AI 表情配合上身动作，不增加 AI 请求。")
                            .font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }
                }.toggleStyle(.switch).tint(Theme.accent).disabled(!enabled)
                    .accessibilityIdentifier("hostEmotionSpeechToggle")
                    .onChange(of:speechLinked) {_,_ in HostEmotionMotionPreference.request("configure",actor:model.runtimeID)}
                HStack(spacing:7) {
                    Image(systemName:"magnifyingglass").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    TextField("找一个动作或心情",text:$search).font(.system(size:12))
                        .focused($searching).submitLabel(.search).onSubmit{searching=false}
                        .accessibilityIdentifier("hostEmotionSearch")
                    if !search.isEmpty {Button {search=""} label:{Image(systemName:"xmark.circle.fill").font(.system(size:11))}
                        .buttonStyle(.plain).accessibilityIdentifier("hostEmotionSearchClear")}
                }.padding(10).background(Theme.surface.opacity(0.5),in:RoundedRectangle(cornerRadius:10))
                ScrollView(.horizontal) {
                    HStack(spacing:6) {
                        category("",label:"全部 \(catalog?.gestures.count ?? 0)")
                        ForEach(catalog?.groups ?? []) {category($0.id,label:$0.label)}
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:126),spacing:7)],spacing:7) {
                    ForEach(gestures) { gesture in
                        Button { HostEmotionMotionPreference.request("preview",actor:model.runtimeID,gesture:gesture.id) } label: {
                            HStack(spacing:7) {
                                Image(systemName:state.hostMotionGesture == gesture.id ? "sparkle" : "play.fill")
                                    .font(.system(size:9)).foregroundStyle(Theme.accent)
                                VStack(alignment:.leading,spacing:3) {
                                    Text(LocalizedStringKey(gesture.label)).font(.system(size:12,weight:.medium))
                                    Text(String(format:"%.1fs",gesture.duration)).font(.system(size:9)).foregroundStyle(Theme.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.padding(.horizontal,11).frame(minHeight:42)
                                .background(Theme.surface.opacity(0.5),in:RoundedRectangle(cornerRadius:11))
                        }.buttonStyle(.plain).disabled(!enabled || !state.ready || !state.hostMotionEnabled)
                            .accessibilityIdentifier("hostEmotionPreview-"+gesture.id)
                    }
                }
                Text("48 个通用组合 · 肩臂幅度更明显，头颈保持合理范围。点按后自然恢复，原作姿势和位置操作优先。语音联动默认关闭，开启后仅在播放语音时执行。")
                    .font(.system(size:10)).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                if state.hostMotionSuppressed {
                    Text("正在保留原作姿势，恢复默认姿势后可预览。")
                        .font(.system(size:10)).foregroundStyle(Theme.peach)
                }
                if !state.hostMotionExpression.isEmpty {
                    Text("配套表情 · "+state.hostMotionExpression).font(.system(size:10)).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("hostEmotionExpression")
                }
            }.padding(.horizontal,18).padding(.bottom,16)
        }.scrollIndicators(.hidden).accessibilityIdentifier("hostEmotionMotionPanel")
        }.softPanelPageSurface().onDisappear {HostEmotionMotionPreference.request("stop",actor:model.runtimeID)}
    }
    private func category(_ id:String,label:String)->some View {
        Button {group=id} label:{Text(LocalizedStringKey(label)).font(.system(size:10,weight:group==id ? .semibold:.regular))
            .padding(.horizontal,10).padding(.vertical,7)
            .foregroundStyle(group==id ? Theme.ink:Theme.secondary)
            .background(Theme.surface.opacity(group==id ? 0.8:0.3),in:Capsule())}
            .buttonStyle(.plain).accessibilityIdentifier("hostEmotionCategory-"+(id.isEmpty ? "all":id))
    }
}
#endif
