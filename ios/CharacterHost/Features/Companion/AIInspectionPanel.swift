#if STARRY_TEST_TOOLS
import SwiftUI

/// Compiled only into opted-in testing builds. The worker independently gates
/// the read-only endpoint and scopes every record to the authenticated owner.
struct AIInspectionPanel:View {
    let model:ModelDescriptor
    let store:CompanionStore
    var draft=""
    @State private var report:AIInspectionReport?
    @State private var failure:String?
    @State private var query=""
    @State private var selectedID:String?
    @State private var childClose=SoftPanelCloseRequest()
    @State private var trigger="user_message"
    @State private var revision=0
    @State private var copied=false
    @State private var reading=false
    @FocusState private var searchFocused:Bool
    private var sections:[AIInspectionReport.Section] {
        (report?.sections ?? []).filter {query.isEmpty || ($0.title+" "+$0.content).localizedCaseInsensitiveContains(query)}
    }
    var body:some View {
        ZStack {
            if let id=selectedID,let section=report?.sections.first(where:{$0.id==id}) {
                AIInspectionSectionPage(section:section)
                    .environment(\.softPanelCloseRequest,childClose).environment(\.softPanelDismiss,{childClose.request()})
                    .id(model.id+"/"+trigger+"/"+id).transition(.opacity)
            } else { overview.transition(.opacity) }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .task(id:"\(trigger)-\(revision)") {await refresh()}
            .accessibilityElement(children:.contain).accessibilityIdentifier("aiInspectionPanel")
    }
    private var overview:some View {
        VStack(spacing:0) {
            PanelPageHeader("AI 设定检查",backID:"closeAIInspector") {
                Button {revision+=1} label:{Image(systemName:"arrow.clockwise").frame(width:36,height:40)}
                    .accessibilityLabel("刷新设定").accessibilityIdentifier("refreshAIInspector")
                Button {if let report {UIPasteboard.general.string=report.fullText;copied=true}} label:{Image(systemName:copied ? "checkmark" : "doc.on.doc").frame(width:36,height:40)}
                    .disabled(report==nil).accessibilityLabel("复制全部设定").accessibilityValue(copied ? "已复制" : "").accessibilityIdentifier("copyAllAISettings")
            }
            VStack(alignment:.leading,spacing:10) {
                Text("测试专用 · \(model.name)").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.accent)
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
                Text("场景改变上下文与请求预览；基础设定在各场景共用。")
                    .font(.system(size:10)).foregroundStyle(Theme.secondary)
            }.padding(.horizontal,22).padding(.bottom,12)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    if let failure {
                        Text(LocalizedStringKey(failure)).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("aiInspectorError")
                    }
                    if reading {ProgressView("正在读取服务端设定").font(.system(size:11))}
                    if let report {
                        Text("\(report.sections.count) 个完整分区 · \(report.capturedAt)").font(.system(size:10)).foregroundStyle(Theme.secondary)
                        ForEach(sections) {section in
                            DeveloperEntry(title:section.title,detail:section.isEmpty ? "尚无此分区的运行记录" : "\(section.content.count) 字符 · 查看完整原文",symbol:section.isEmpty ? "tray" : "doc.text",id:"aiInspectionSection-"+section.id) {
                                searchFocused=false
                                childClose=SoftPanelCloseRequest()
                                childClose.begin {withAnimation(.easeInOut(duration:0.2)) {selectedID=nil}}
                                withAnimation(.easeInOut(duration:0.2)) {selectedID=section.id}
                            }

                        }
                    }
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()

    }
    private func refresh() async {
        report=nil;failure=nil;copied=false;selectedID=nil;reading=true
        defer {reading=false}
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),ProcessInfo.processInfo.arguments.contains("--inspector-layout-fixture") {
            report=AIInspectionReport(version:1,characterId:model.id,capturedAt:"布局验证",sections:[
                .init(id:"persona",title:"完整角色设定",detail:"角色源配置",content:"角色专属设定："+model.name),
                .init(id:"prompts",title:"全部提示词",detail:"生成规则原文",content:"对话规划与叙述规则"),
                .init(id:"context",title:"本轮上下文预览",detail:"场景上下文",content:"当前触发场景："+trigger),
                .init(id:"latency",title:"最近回复耗时",detail:"独立运行记录",content:"{}")])
            return
        }
#endif
        let local=localSections()
        report=AIInspectionReport(version:1,characterId:model.id,capturedAt:"本机资料",sections:local)
        do {
            let api=CharacterAI(accountID:store.accountID,characterID:model.id)
            var value:AIInspectionReport=try await api.configuration("/v1/testing/characters/"+model.id+"/inspector",body:CompanionSession.requestBody(store:store,model:model,text:draft,trigger:trigger))
            try Task.checkCancellation()
            guard store.accountID==api.accountID else {return}
            value.sections.append(contentsOf:local)
            guard value.characterId == model.id, Set(value.sections.map(\.id)).count == value.sections.count else {
                failure="报告的角色或分区标识不匹配，请刷新后重试。";return
            }
            report=value
        } catch is CancellationError {} catch {
            switch error {
            case AIConnectionError.authenticationRequired,AIConnectionError.server(401):
                failure="请登录已授权的开发账号后刷新。当前仅显示本机资料，服务端完整设定尚未读取。"
            case AIConnectionError.server(403):
                failure="当前账号未开通服务端设定检查。当前仅显示本机资料；该权限由服务器管理员配置。"
            case AIConnectionError.server(404):
                failure="服务端设定检查入口或当前角色不可用。请确认账号授权与服务端入口，当前仍可查看本机资料。"
            default:
                failure="暂时无法读取服务端完整设定，请检查网络后刷新。当前仅显示本机资料。"
            }
        }
    }
    private func localSections()->[AIInspectionReport.Section] {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        let record=store.record(model.id)
        func json<T:Encodable>(_ value:T)->String {(try? String(decoding:encoder.encode(value),as:UTF8.self)) ?? "无法编码"}
        var result:[AIInspectionReport.Section]=[.init(id:"local",title:"本机全部相处资料",detail:"完整偏好、全部本机记忆、用户侧展示设定与问候记录；服务端本轮使用的部分见请求预览。",content:
            "称呼解析\n"+json(["全局默认":store.defaultNickname,"角色专属":record.together.preferences.nickname,"实际称呼":store.effectiveNickname(for:model.id),"来源":store.nicknameSource(for:model.id)])+"\n相处偏好\n"+json(record.together.preferences)+"\n全部记忆\n"+json(record.memories)+"\n本机展示与声音设置\n"+json(record.profile)+"\n问候记录\n"+json(record.greeting))]
        if let url=Bundle.main.url(forResource:"ClientAIRules",withExtension:"txt"),let text=try? String(contentsOf:url,encoding:.utf8) {
            result.append(.init(id:"native-rules",title:"App 端执行规则",detail:"此测试安装包的会话、问候、语音和缓存完整源码。",content:text))
        }
        return result
    }
}

/// Separate identity and scroll state per section prevents a previously opened
/// page from retaining another section's text. Empty runtime traces are labelled
/// explicitly instead of several apparently identical "{}" pages.
private struct AIInspectionSectionPage:View {
    let section:AIInspectionReport.Section
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader(section.title,backID:"closeAIInspectionSection") {
                Button {UIPasteboard.general.string=section.content} label: {
                    Image(systemName:"doc.on.doc").frame(width:36,height:40)
                }.accessibilityLabel("复制本分区原文")
            }
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    Text(section.detail).font(.system(size:12)).foregroundStyle(Theme.secondary)
                    Text("分区 · "+section.id).font(.system(size:10,design:.monospaced)).foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("aiInspectionSectionID")
                    if section.isEmpty {
                        Text("「\(section.title)」暂无记录").font(.system(size:16,weight:.medium))
                        Text("尚未产生这一类数据。执行对应场景后再刷新即可查看，不会用其他分区的内容代替。")
                            .font(.system(size:12)).foregroundStyle(Theme.secondary)
                    }
                    Text(section.content).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal:false,vertical:true)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .accessibilityIdentifier("aiInspectionContent-"+section.id)
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden)
        }.softPanelPageSurface().accessibilityElement(children:.contain).accessibilityIdentifier("aiInspectionDetail-"+section.id)
    }
}
#endif
