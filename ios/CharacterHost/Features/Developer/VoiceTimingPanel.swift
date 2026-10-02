#if STARRY_TEST_TOOLS
import SwiftUI

struct VoiceTimingPanel:View {
    let account:String
    var character:String? = nil
    var initialSelection:String? = nil
    @State private var timeline=VoiceTimeline.shared
    @State private var selected:String?
    @State private var all=false
    private var records:[VoiceRecord] {Array(timeline.records.filter {$0.account==account && (character==nil || $0.character==character)}.reversed())}
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader("语音耗时",backID:"closeVoiceTimings")
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("客户端与服务端使用同一追踪 ID。横条重叠表示并行；生成时间、播放时间分别记录。日志不含对话正文、音频或凭证。")
                        .font(.system(size:12)).foregroundStyle(Theme.secondary)
                    if let id=selected,let record=records.first(where:{$0.id==id}) {
                        Button("返回语音列表") {withAnimation(.easeInOut(duration:0.2)) {selected=nil}}.font(.system(size:12))
                        detail(record)
                    } else {
                        Text("最近 \(records.count) 次 · 重启后保留").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.secondary)
                        if records.isEmpty {Text("进行一次对话、重播语音或按住说话后，这里会显示分段记录。").font(.system(size:13))}
                        ForEach(records) {record in
                            Button {withAnimation(.easeInOut(duration:0.2)) {selected=record.id;all=false}} label:{
                                HStack(alignment:.top) {
                                    VStack(alignment:.leading,spacing:5) {
                                        Text(ModelDescriptor.all.first(where:{$0.id==record.character})?.name ?? record.character).font(.system(size:14,weight:.medium))
                                        Text(record.kind+" · "+record.status).font(.system(size:11)).foregroundStyle(Theme.secondary)
                                        Text(record.created.formatted(date:.omitted,time:.standard)).font(.system(size:10)).foregroundStyle(Theme.secondary)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    VStack(alignment:.trailing,spacing:4) {
                                        Text(record.marks["first_output"].map(VoiceStage.time) ?? "尚未出声").font(.system(size:13,design:.monospaced))
                                        Text("到首次输出").font(.system(size:10)).foregroundStyle(Theme.secondary)
                                    }
                                }.padding(14).background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:14))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .accessibilityIdentifier("voiceTimingPanel")
            .onAppear {if selected==nil {selected=initialSelection}}
    }
    @ViewBuilder private func detail(_ record:VoiceRecord)->some View {
        VStack(alignment:.leading,spacing:12) {
            Text(record.id).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
            Text(record.kind+" · "+record.status).font(.system(size:12)).foregroundStyle(Theme.secondary)
            HStack {
                milestone("文字到达",record.marks["text_received"])
                milestone("音频到达",record.marks["first_audio_received"])
                milestone("首次输出",record.marks["first_output"])
            }
            if let longest=record.spans.filter({!$0.name.hasSuffix("drain")}).max(by:{$0.durationMs<$1.durationMs}) {
                Text("最长客户端环节：\(VoiceStage.title(longest.name)) · \(VoiceStage.time(longest.durationMs))").font(.system(size:12)).foregroundStyle(Theme.accent)
            }
            ForEach(record.flags.keys.sorted(),id:\.self) {key in
                Text(key+"："+(record.flags[key] ?? "")).font(.system(size:11,design:.monospaced)).foregroundStyle(Theme.secondary)
            }
            Toggle("显示每段音频的全部环节",isOn:$all).font(.system(size:12))
            Text("客户端时间轴").font(.system(size:15,weight:.medium))
            waterfall(record.spans,total:record.totalMs)
            Text("输出时刻由音频混音器检测，含主线程回调延迟，不代表耳边测得的物理声学延迟。DNS/TLS 无值可能是连接复用，不按零耗时推断。")
                .font(.system(size:11)).foregroundStyle(Theme.secondary)
            if let server=record.server {
                Text("服务端时间轴").font(.system(size:15,weight:.medium)).padding(.top,6)
                Text("\(server.kind) · \(server.status) · \(VoiceStage.time(server.totalMs))").font(.system(size:12))
                ForEach(server.gateway.keys.sorted(),id:\.self) {key in
                    Text(key+"："+VoiceStage.time(server.gateway[key] ?? 0)).font(.system(size:11,design:.monospaced))
                }
                ForEach(server.flags.keys.sorted(),id:\.self) {key in
                    Text(key+"："+(server.flags[key]?.label ?? "")).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                }
                waterfall(server.spans,total:server.totalMs)
            } else {
                Text("此条尚无服务端快照。内置首句和本地缓存重播不调用服务器；中断请求可用追踪 ID 到管理平台查找。")
                    .font(.system(size:11)).foregroundStyle(Theme.secondary)
            }
            if let json=try? JSONEncoder().encode(record),let text=String(data:json,encoding:.utf8) {
                ShareLink(item:text) {Label("导出完整耗时记录",systemImage:"square.and.arrow.up")}.font(.system(size:13))
            }
        }.padding(14).background(Theme.surface.opacity(0.55),in:RoundedRectangle(cornerRadius:16))
    }
    private func milestone(_ name:String,_ value:Double?)->some View {
        VStack(alignment:.leading,spacing:5) {Text(name).font(.system(size:10)).foregroundStyle(Theme.secondary);Text(value.map(VoiceStage.time) ?? "—").font(.system(size:12,design:.monospaced))}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func waterfall(_ spans:[VoiceSpan],total:Double)->some View {
        let shown=spans.filter {all || $0.durationMs>=1 || $0.name=="audio.cache_read"}
        let extent=max(1,total,spans.map {$0.startMs+$0.durationMs}.max() ?? 0)
        return VStack(alignment:.leading,spacing:12) {
            ForEach(Array(shown.enumerated()),id:\.offset) {_,span in
                VStack(alignment:.leading,spacing:5) {
                    HStack(alignment:.top) {Text(VoiceStage.title(span.name)).font(.system(size:11));Spacer(minLength:8);Text(VoiceStage.time(span.durationMs)).font(.system(size:11,design:.monospaced))}
                    GeometryReader {geometry in
                        ZStack(alignment:.leading) {
                            Capsule().fill(Theme.secondary.opacity(0.08))
                            Capsule().fill(Theme.accent.opacity(0.65)).frame(width:max(2,geometry.size.width*span.durationMs/extent)).offset(x:geometry.size.width*span.startMs/extent)
                        }
                    }.frame(height:5).clipped()
                    Text(spanDetail(span))
                        .font(.system(size:9,design:.monospaced)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
    private func spanDetail(_ span:VoiceSpan)->String {
        var parts=["+"+VoiceStage.time(span.startMs)]
        if let beat=span.beatId {parts.append(beat)}
        if let bytes=span.bytes {parts.append("\(bytes) B")}
        if let duration=span.audioDurationMs {parts.append("音频长度 "+VoiceStage.time(duration))}
        if let attempt=span.attempt {parts.append("第 \(attempt) 次尝试")}
        if let model=span.model {parts.append(model)}
        return parts.joined(separator:" · ")
    }
}
#endif
