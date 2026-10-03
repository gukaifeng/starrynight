import SwiftUI

// HOST-EMOTION-EXPERIMENT v2. Developer preview, deliberately independent of
// XCP author selections and account/character customization records.
enum HostEmotionMotionPreference {
    static let key = "hostEmotionMotionEnabled.v1"
    static let notification = Notification.Name("HostEmotionMotionRequest.v1")
    static var enabled: Bool { UserDefaults.standard.object(forKey:key) as? Bool ?? true }
    static func request(_ kind:String,actor:String,gesture:String = "") {
        NotificationCenter.default.post(name:notification,object:nil,userInfo:["kind":kind,"actor":actor,"gesture":gesture])
    }
}

#if STARRY_TEST_TOOLS
struct HostEmotionMotionPanel: View {
    let model:ModelDescriptor
    let state:CharacterPerformanceState
    @AppStorage(HostEmotionMotionPreference.key) private var enabled=true
    private let gestures=[("agree","轻轻点头"),("happy","开心回应"),("curious","侧头思考"),
                          ("shy","害羞低头"),("pout","小小不满"),("sad","低落倾听"),("surprised","惊讶回应"),
                          ("welcome","挥手问好"),("encourage","温柔鼓励"),("disagree","轻轻摇头")]
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
                        Text("仅开发者手动预览 · 不接入正式对话")
                            .font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }
                }.toggleStyle(.switch).tint(Theme.accent)
                    .accessibilityIdentifier("hostEmotionMotionToggle")
                    .onChange(of:enabled) { _,_ in HostEmotionMotionPreference.request("configure",actor:model.runtimeID) }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:126),spacing:7)],spacing:7) {
                    ForEach(gestures,id:\.0) { id,label in
                        Button { HostEmotionMotionPreference.request("preview",actor:model.runtimeID,gesture:id) } label: {
                            HStack(spacing:7) {
                                Image(systemName:state.hostMotionGesture == id ? "sparkle" : "play.fill")
                                    .font(.system(size:9)).foregroundStyle(Theme.accent)
                                Text(LocalizedStringKey(label)).font(.system(size:12,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading)
                            }.padding(.horizontal,11).frame(minHeight:42)
                                .background(Theme.surface.opacity(0.5),in:RoundedRectangle(cornerRadius:11))
                        }.buttonStyle(.plain).disabled(!enabled || !state.ready || !state.hostMotionEnabled)
                            .accessibilityIdentifier("hostEmotionPreview-"+id)
                    }
                }
                Text("10 个通用组合 · 点按后自然回到原姿态。角色原作表现和位置操作优先，关闭此实验保留原作能力。")
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
}
#endif
