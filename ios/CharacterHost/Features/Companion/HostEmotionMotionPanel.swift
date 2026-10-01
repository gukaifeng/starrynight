import SwiftUI

// HOST-EMOTION-EXPERIMENT v1. Local app preference, deliberately independent of
// XCP author selections and account/character customization records.
enum HostEmotionMotionPreference {
    static let key = "hostEmotionMotionEnabled.v1"
    static let notification = Notification.Name("HostEmotionMotionRequest.v1")
    static var enabled: Bool { UserDefaults.standard.object(forKey:key) as? Bool ?? true }
    static func request(_ kind:String,actor:String,gesture:String = "") {
        NotificationCenter.default.post(name:notification,object:nil,userInfo:["kind":kind,"actor":actor,"gesture":gesture])
    }
}

struct HostEmotionMotionPanel: View {
    let model:ModelDescriptor
    let state:CharacterPerformanceState
    @AppStorage(HostEmotionMotionPreference.key) private var enabled=true
    private let gestures=[("agree","轻轻点头"),("happy","开心回应"),("curious","侧头思考"),
                          ("shy","害羞低头"),("pout","小小不满"),("sad","低落倾听"),("surprised","惊讶回应")]
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:10) {
                Toggle(isOn:$enabled) {
                    VStack(alignment:.leading,spacing:3) {
                        Text("附加情绪动作").font(.system(size:13,weight:.medium))
                        Text("星夜试验 · 关闭后仍保留角色原作表现")
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
                Text("点按预览身体动作。对话时随原作表情自动搭配；原作姿势和位置操作优先。")
                    .font(.system(size:10)).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                if state.hostMotionSuppressed {
                    Text("正在保留原作姿势，恢复默认姿势后可预览。")
                        .font(.system(size:10)).foregroundStyle(Theme.peach)
                }
            }.padding(.horizontal,18).padding(.bottom,16)
        }.scrollIndicators(.hidden).accessibilityIdentifier("hostEmotionMotionPanel")
    }
}
