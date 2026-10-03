#if STARRY_TEST_TOOLS
import SwiftUI

/// These pages and their entry points are compiled out of distribution projects.
struct CharacterDeveloperPanel:View {
    let model:ModelDescriptor
    let store:CompanionStore
    var session:CompanionSession? = nil
    var performanceState:CharacterPerformanceState? = nil
    var onSelect:(String,Bool)->Void = {_,_ in}
    var onReset:(String)->Void = {_ in}
    var onAdjust:(String,Double)->Void = {_,_ in}
    var onVisibility:(Bool)->Void = {_ in}
    var onOpenConversation:()->Void = {}
    @State private var destination:String?
    @State private var catalogState=CharacterPerformanceState()
    @State private var childClose=SoftPanelCloseRequest()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func open(_ value:String) {
        childClose=SoftPanelCloseRequest()
        childClose.begin {withAnimation(.easeInOut(duration:0.2)) {destination=nil}}
        withAnimation(.easeInOut(duration:reduceMotion ? 0.1 : 0.25)) {destination=value}
    }
    var body:some View {
        ZStack {
            if destination == "voice" {
                VoiceTimingPanel(account:store.accountID,character:model.id)
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()}).transition(.opacity)
            } else if destination == "ai" {
                AIInspectionPanel(model:model,store:store,draft:session?.input ?? "")
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()})
                    .transition(.opacity)
            } else if destination == "motion",let state=performanceState {
                HostEmotionMotionPanel(model:model,state:state)
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()}).transition(.opacity)
            } else if (destination == "performance" || destination == "source"),let profile=model.performance {
                CharacterPerformancePanel(model:model,profile:profile.scopedToSourceLibrary(destination == "source"),state:performanceState ?? catalogState,onSelect:onSelect,onReset:onReset,
                    onAdjust:onAdjust,onVisibilityChanged:onVisibility,sourceLibrary:destination == "source",onOpenPreview:performanceState == nil ? onOpenConversation : nil)
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()})
                    .transition(.opacity)
            } else {
                VStack(spacing:0) {
                    PanelPageHeader("角色开发者 · "+model.name,backID:"closeCharacterDeveloper")
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            Text("开发构建专用").font(.system(size:11,weight:.medium)).foregroundStyle(Theme.accent)
                            DeveloperEntry(title:"AI 设定检查",detail:"完整设定、提示词、上下文与实际请求",symbol:"curlybraces",id:"openAIInspector") {open("ai")}
                            DeveloperEntry(title:"语音耗时",detail:"生成、网络、缓存、排队与播放的逐次拆解",symbol:"waveform.path",id:"openCharacterVoiceTimings") {open("voice")}
                            if let state=performanceState,state.hostMotionSupported {
                                DeveloperEntry(title:"动作实验",detail:"10 个通用身体与表情组合 · 仅手动预览",symbol:"figure.wave",id:"openHostEmotionMotion") {open("motion")}
                            }
                            if model.performance != nil {
                                DeveloperEntry(title:"角色表现",detail:"手动检查原生表情、动作和物理能力",symbol:"theatermasks",id:"profilePerformanceButton") {open("performance")}
                                if let library=model.performance?.scopedToSourceLibrary(true),!library.options.isEmpty {
                                    DeveloperEntry(title:"原作片段库",detail:"\(library.options.count) 个可绑定片段 · 肢体、表情与部件",symbol:"film.stack",id:"openSourceMotionLibrary") {open("source")}
                                }
                            } else {
                                Text("当前角色的表现目录暂未就绪。请退出本页后重新进入会话；已下载的角色可在存储与缓存中重新下载资源。")
                                    .font(.system(size:12)).foregroundStyle(Theme.secondary).accessibilityIdentifier("performanceCatalogUnavailable")
                            }
                            VStack(alignment:.leading,spacing:8) {
                                Text("资源与能力").font(.system(size:14,weight:.medium))
                                Text("角色 ID：\(model.id)\n资源版本：\(model.packageVersion)\n动作选项：\(model.performance?.options.count ?? 0)\n能力分组：\(model.performance?.groups.map(\.label).joined(separator:"、") ?? "无")")
                                    .font(.system(size:12,design:.monospaced)).textSelection(.enabled).foregroundStyle(Theme.secondary)
                                Text("手动预览仅供开发检查；对话与场景触发保持自动运行。")
                                    .font(.system(size:11)).foregroundStyle(Theme.secondary)
                            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Theme.surface.opacity(0.55),in:RoundedRectangle(cornerRadius:16))
                        }.padding(.horizontal,22).padding(.bottom,20)
                    }.scrollIndicators(.hidden)
                }.transition(.opacity)
            }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .accessibilityElement(children:.contain).accessibilityIdentifier("characterDeveloperPanel")
    }
}

struct AppDeveloperPanel:View {
    let coordinator:ViewerCoordinator
    var onOpenCharacter:(String)->Void
    @State private var selected:ModelDescriptor?
    @State private var voiceTimings=false
    @State private var childClose=SoftPanelCloseRequest()
    var body:some View {
        ZStack {
            if voiceTimings {
                VoiceTimingPanel(account:coordinator.companionStore.accountID)
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()}).transition(.opacity)
            } else if let selected {
                CharacterDeveloperPanel(model:selected,store:coordinator.companionStore,onOpenConversation:{onOpenCharacter(selected.id)})
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()})
                    .id(selected.id).transition(.opacity)
            } else {
                VStack(spacing:0) {
                    PanelPageHeader("星夜开发者",backID:"closeAppDeveloper")
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            Text("开发构建 · 不随正式版本分发").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.accent)
                            DeveloperEntry(title:"语音耗时",detail:"所有角色的逐次耗时、服务端快照与日志导出",symbol:"waveform.path",id:"openAppVoiceTimings") {
                                childClose=SoftPanelCloseRequest()
                                childClose.begin {withAnimation(.easeInOut(duration:0.2)) {voiceTimings=false}}
                                withAnimation(.easeInOut(duration:0.2)) {voiceTimings=true}
                            }
                            VStack(alignment:.leading,spacing:8) {
                                let info=Bundle.main.infoDictionary ?? [:]
                                Text("版本 \(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))")
                                Text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(ModelDescriptor.all.count) 个内置角色")
                                Text("AI 设定检查只读，不生成回复、不消耗模型用量。账号凭证和 API 密钥不会显示。")
                            }.font(.system(size:12)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            Text("角色检查").font(.system(size:15,weight:.medium)).padding(.top,8)
                            ForEach(ModelDescriptor.all) {model in
                                DeveloperEntry(title:model.name,detail:model.id,symbol:"person.crop.circle",id:"developerCharacter-"+model.id) {
                                    childClose=SoftPanelCloseRequest()
                                    childClose.begin {withAnimation(.easeInOut(duration:0.2)) {selected=nil}}
                                    withAnimation(.easeInOut(duration:0.2)) {selected=model}
                                }
                            }
                        }.padding(.horizontal,22).padding(.bottom,24)
                    }.scrollIndicators(.hidden)
                }.transition(.opacity)
            }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface(opaque:true)
            .accessibilityElement(children:.contain).accessibilityIdentifier("appDeveloperPanel")
    }
}

struct DeveloperEntry:View {
    let title,detail,symbol,id:String
    var action:()->Void
    var body:some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:symbol).frame(width:24).foregroundStyle(Theme.accent)
                VStack(alignment:.leading,spacing:4) {
                    Text(LocalizedStringKey(title)).font(.system(size:14,weight:.medium))
                    Text(LocalizedStringKey(detail)).font(.system(size:11)).foregroundStyle(Theme.secondary).lineLimit(2)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Theme.secondary)
            }.padding(14).background(Theme.surface.opacity(0.6),in:RoundedRectangle(cornerRadius:15)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
#endif
