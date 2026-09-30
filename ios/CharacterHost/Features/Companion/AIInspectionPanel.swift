#if STARRY_TEST_TOOLS
import SwiftUI

/// Compiled only into opted-in testing builds. The worker independently gates
/// the read-only endpoint and scopes every record to the authenticated owner.
struct AIInspectionPanel:View {
    let session:CompanionSession
    @State private var report:AIInspectionReport?
    @State private var failure:String?
    @State private var query=""
    @State private var expanded:String?="persona"
    @State private var trigger="user_message"
    @State private var revision=0
    @State private var copied=false
    @FocusState private var searchFocused:Bool
    private var sections:[AIInspectionReport.Section] {
        (report?.sections ?? []).filter {query.isEmpty || ($0.title+" "+$0.content).localizedCaseInsensitiveContains(query)}
    }
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader("AI 设定检查",backID:"closeAIInspector") {
                Button {revision+=1} label:{Image(systemName:"arrow.clockwise").frame(width:36,height:40)}
                    .accessibilityLabel("刷新设定").accessibilityIdentifier("refreshAIInspector")
                Button {if let report {UIPasteboard.general.string=report.fullText;copied=true}} label:{Image(systemName:copied ? "checkmark" : "doc.on.doc").frame(width:36,height:40)}
                    .disabled(report==nil).accessibilityLabel("复制全部设定").accessibilityValue(copied ? "已复制" : "").accessibilityIdentifier("copyAllAISettings")
            }
            VStack(alignment:.leading,spacing:10) {
                Text("测试专用 · \(session.model.name)").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.accent)
                Text("查看完整配置、当前上下文和实际请求。刷新不会生成回复或消耗 AI 用量。")
                    .font(.system(size:12)).foregroundStyle(Theme.secondary)
                HStack {
                    Image(systemName:"magnifyingglass").font(.system(size:13))
                    TextField("搜索全部设定",text:$query).font(.system(size:14)).focused($searchFocused)
                        .submitLabel(.done).onSubmit {searchFocused=false}.accessibilityIdentifier("aiSettingsSearch")
                }.padding(11).background(Theme.surface.opacity(0.7),in:RoundedRectangle(cornerRadius:14))
                Picker("预览场景",selection:$trigger) {
                    Text("对话").tag("user_message");Text("启动").tag("appLaunch");Text("切换角色").tag("characterSwitch");Text("待机").tag("idle")
                }.pickerStyle(.segmented).accessibilityIdentifier("aiInspectorTrigger")
            }.padding(.horizontal,22).padding(.bottom,12)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    if let failure {
                        Text(failure).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("aiInspectorError")
                    } else if let report {
                        Text("\(report.sections.count) 个完整分区 · \(report.capturedAt)").font(.system(size:10)).foregroundStyle(Theme.secondary)
                        ForEach(sections) {section in
                            DisclosureGroup(isExpanded:Binding(get:{expanded==section.id},set:{expanded=$0 ? section.id : nil})) {
                                VStack(alignment:.leading,spacing:12) {
                                    Text(section.detail).font(.system(size:12)).foregroundStyle(Theme.secondary)
                                    Text(section.content).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("aiInspectionContent-"+section.id)
                                }.padding(.top,10).frame(maxWidth:.infinity,alignment:.leading)
                            } label: {
                                VStack(alignment:.leading,spacing:4) {
                                    Text(section.title).font(.system(size:14,weight:.medium))
                                    Text("\(section.content.count) 字符 · 完整原文").font(.system(size:10)).foregroundStyle(Theme.secondary)
                                }
                            }.padding(15).background(Theme.surface.opacity(0.6),in:RoundedRectangle(cornerRadius:17))
                                .accessibilityElement(children:.contain).accessibilityIdentifier("aiInspectionSection-"+section.id)
                        }
                    } else {ProgressView().frame(maxWidth:.infinity).padding(30)}
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .task(id:"\(trigger)-\(revision)") {await refresh()}
            .onChange(of:expanded) {_,_ in searchFocused=false}
            .accessibilityElement(children:.contain).accessibilityIdentifier("aiInspectionPanel")
    }
    private func refresh() async {
        report=nil;failure=nil;copied=false
        do {
            var value:AIInspectionReport=try await session.api.configuration("/v1/testing/characters/"+session.model.id+"/inspector",body:session.requestBody(session.input,trigger:trigger))
            try Task.checkCancellation()
            guard session.store.accountID==session.api.accountID else {return}
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
            let record=session.record
            func json<T:Encodable>(_ value:T)->String {(try? String(decoding:encoder.encode(value),as:UTF8.self)) ?? "无法编码"}
            value.sections.append(.init(id:"local",title:"本机全部相处资料",detail:"完整偏好、全部本机记忆、用户侧展示设定与问候记录；真正送入本轮的部分见请求预览。",content:
                "相处偏好\n"+json(record.together.preferences)+"\n全部记忆\n"+json(record.memories)+"\n本机展示与声音设置\n"+json(record.profile)+"\n问候记录\n"+json(record.greeting)))
            if let url=Bundle.main.url(forResource:"ClientAIRules",withExtension:"txt"),let text=try? String(contentsOf:url,encoding:.utf8) {
                value.sections.append(.init(id:"native-rules",title:"App 端执行规则",detail:"此测试安装包的会话、问候、语音和缓存完整源码。",content:text))
            }
            report=value
        } catch is CancellationError {} catch {
            failure="暂时无法读取完整设定。请确认测试 AI 服务已连接并已开启设定检查；普通部署不会开放这个入口。"
        }
    }
}
#endif
