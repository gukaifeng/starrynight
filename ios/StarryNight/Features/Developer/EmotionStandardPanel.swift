#if STARRY_TEST_TOOLS
import SwiftUI
struct EmotionStandardPanel:View {
    let model:ModelDescriptor
    let state:CharacterPerformanceState
    @State private var kind="emotion"
    @State private var search=""
    @FocusState private var searching:Bool
    private var entries:[EmotionPerformanceCatalog.Entry] {(EmotionPerformanceCatalog.shared?.entries ?? []).filter {$0.kind==kind && (search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search))}}
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader("情感表演 · "+model.name,backID:"closeEmotionStandard") {
                Button {HostEmotionMotionPreference.request("stop",actor:model.runtimeID)} label:{Image(systemName:"stop.circle").font(.system(size:15)).foregroundStyle(Theme.secondary)}.buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text("42 项标准 · 每项 3 组 · 126 组表演").font(.system(size:13,weight:.medium))
                    Text("以下是 \(model.name) 的实际匹配。点播放仅预览表情与动作，不请求合成声音。正常对话按每句的情绪、风格与拟声自动联动。")
                        .font(.system(size:11)).foregroundStyle(Theme.secondary)
                    Text("已匹配 \(state.emotionMappings.count) 项").font(.system(size:10)).foregroundStyle(Theme.secondary).accessibilityIdentifier("emotionStandardMappingSummary")
                    Picker("类别",selection:$kind) {Text("情绪 28").tag("emotion");Text("发声风格 7").tag("style");Text("拟声 7").tag("vocal")}.pickerStyle(.segmented).accessibilityIdentifier("emotionStandardKind").onChange(of:kind){_,_ in search="";searching=false}
                    TextField("查找标签或心情",text:$search).accessibilityIdentifier("emotionStandardSearch").focused($searching).submitLabel(.search).onSubmit{searching=false}.font(.system(size:12)).padding(10).background(Theme.surface.opacity(0.5),in:RoundedRectangle(cornerRadius:10))
                    ForEach(entries,id:\.key) {entry in
                        let mapping=state.emotionMappings.first(where:{$0.key==entry.key})
                        VStack(alignment:.leading,spacing:8) {
                            HStack {Text(entry.label).font(.system(size:13,weight:.medium));Spacer();Text(entry.providerTag.isEmpty ? "自然语言指令": "["+entry.providerTag+"]").font(.system(size:10,design:.monospaced)).foregroundStyle(Theme.secondary)}
                            ForEach(Array(entry.variants.enumerated()),id:\.element.id) {index,variant in
                                Button {HostEmotionMotionPreference.request("preview",actor:model.runtimeID,gesture:variant.id)} label:{
                                    HStack(spacing:9) {
                                        Image(systemName:state.hostMotionGesture==variant.id ? "sparkle":"play.fill").font(.system(size:10)).foregroundStyle(Theme.accent)
                                        VStack(alignment:.leading,spacing:3) {
                                            Text("\(index+1) · "+variant.label).font(.system(size:12))
                                            Text(mapping?.faces.indices.contains(index)==true ? mapping!.faces[index]:"等待角色匹配表情").font(.system(size:10)).foregroundStyle(Theme.secondary)
                                        }
                                        Spacer();Text(String(format:"%.1fs",variant.duration)).font(.system(size:10)).foregroundStyle(Theme.secondary)
                                    }.padding(.vertical,5).frame(minHeight:44).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(!state.ready || !state.hostMotionEnabled).accessibilityIdentifier("standardPreview-"+variant.id)
                            }
                            if let mapping {
                                Text("已适配："+mapping.channels.joined(separator:" · ")).font(.system(size:10)).foregroundStyle(Theme.secondary)
                                if !mapping.originalOptions.isEmpty {Text("原作配合："+mapping.originalOptions.joined(separator:"、")).font(.system(size:10)).foregroundStyle(Theme.secondary)}
                                if !mapping.unavailable.isEmpty {Text("无专属动作："+mapping.unavailable.joined(separator:"、")+"；保持原作物理或用身体表演替代。")
                                    .font(.system(size:10)).foregroundStyle(Theme.peach)}
                            }
                        }.padding(12).background(Theme.surface.opacity(0.45),in:RoundedRectangle(cornerRadius:13))
                    }
                    Text("原作完整姿势、手动动作与模型调整优先。没有的耳朵、尾巴或饰物骨骼不强行生成；已有头发、衣物和饰物的物理跟随持续工作。")
                        .font(.system(size:10)).foregroundStyle(Theme.secondary)
                }.padding(.horizontal,18).padding(.bottom,20)
            }.scrollIndicators(.hidden).accessibilityIdentifier("emotionStandardPanel")
        }.softPanelPageSurface().onAppear {HostEmotionMotionPreference.request("mapping",actor:model.runtimeID)}
            .onDisappear {HostEmotionMotionPreference.request("stop",actor:model.runtimeID)}
    }
}
#endif
