import SwiftUI
import Observation

/// Only matching engine events commit selections. New presentations start unconfirmed,
/// so a retained SwiftUI sheet can never echo another character's selected options.
@MainActor @Observable final class CharacterPerformanceState {
    private(set) var modelID = ""
    private(set) var presentation = -1
    private(set) var selections = Set<String>()
    private(set) var controlValues: [String:Double] = [:]
    private(set) var ready = false
    private(set) var transitioning = false
    private(set) var pendingID: String?
    private(set) var pendingOption: String?
    private(set) var error: String?
    private(set) var hostMotionSupported=false
    private(set) var hostMotionEnabled=false
    private(set) var hostMotionSuppressed=false
    private(set) var hostMotionGesture=""
    private(set) var hostMotionExpression=""
    private(set) var hostMotionExpressions:[String]=[]
#if DEBUG
    private(set) var confirmedCounts: [String:Int] = [:]
#endif

    func begin(modelID: String, presentation: Int) {
        self.modelID = modelID; self.presentation = presentation
        selections.removeAll(); controlValues.removeAll(); ready = false; transitioning = false
        pendingID = nil; pendingOption = nil; error = nil
        hostMotionSupported=false;hostMotionEnabled=false;hostMotionSuppressed=false;hostMotionGesture=""
        hostMotionExpression="";hostMotionExpressions=[]
#if DEBUG
        confirmedCounts.removeAll()
#endif
    }
    func request(id: String, option: String) {
        pendingID = id; pendingOption = option; error = nil
    }
    func timeout(_ id: String) {
        guard pendingID == id else { return }
        pendingID = nil; pendingOption = nil
        error = "还没有收到角色的回应，可以再试一次。"
    }
    func receive(_ event: [String: Any]) {
        guard event["modelId"] as? String == modelID,
              event["presentationId"] as? Int == presentation else { return }
        if let platform = event["characterPlatform"] as? [String: Any],
           let selected = platform["performanceSelections"] as? [String] {
            if let motion=platform["hostEmotionMotion"] as? [String:Any] {
                hostMotionSupported=motion["supported"] as? Bool ?? false
                hostMotionEnabled=motion["enabled"] as? Bool ?? false
                hostMotionSuppressed=motion["suppressed"] as? Bool ?? false
                hostMotionGesture=motion["gesture"] as? String ?? ""
                hostMotionExpression=motion["expression"] as? String ?? ""
                hostMotionExpressions=motion["expressions"] as? [String] ?? []
            }
            selections = Set(selected); ready = true
            transitioning = platform["performanceTransitioning"] as? Bool ?? false
            if let values=platform["avatarControlValues"] as? [[String:Any]] {
                controlValues=Dictionary(values.compactMap { row -> (String,Double)? in
                    guard let id=row["id"] as? String,let value=row["value"] as? Double else {return nil}
                    return (id,value)
                },uniquingKeysWith: { _,new in new })
            }
        }
#if DEBUG
        if let receipt=event["receipt"] as? [String:Any],receipt["eventName"] as? String == "performance.select",
           receipt["status"] as? String == "accepted",let target=receipt["target"] as? String,
           selections.contains(target) { confirmedCounts[target,default:0] += 1 }
#endif
        if let receipt = event["receipt"] as? [String: Any],
           let id = pendingID, receipt["eventId"] as? String == id {
            pendingID = nil; pendingOption = nil
            error = receipt["status"] as? String == "accepted" ? nil : "这个表现暂时没有完成，请再试一次。"
        }
    }
}

#if STARRY_TEST_TOOLS
struct CharacterPerformancePanel: View {
    let model: ModelDescriptor
    let profile: CharacterPerformanceProfile
    let state: CharacterPerformanceState
    var onSelect: (String, Bool) -> Void
    var onReset: (String) -> Void
    var onAdjust: (String, Double) -> Void = { _,_ in }
    var onVisibilityChanged: (Bool) -> Void = { _ in }
    var sourceLibrary=false
    var onOpenPreview:(()->Void)? = nil
    @State private var selectedGroup = ""
    @State private var search=""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [CharacterPerformanceProfile.Group] {
        profile.groups.filter { group in profile.options.contains { $0.group == group.id } }
    }
    private var currentGroup: String { groups.contains { $0.id == selectedGroup } ? selectedGroup : groups.first?.id ?? "" }
    private var options: [CharacterPerformanceProfile.Option] {
        profile.options.filter {$0.group == currentGroup && (search.isEmpty || $0.label.localizedCaseInsensitiveContains(search))}
    }
    private var canSelect: Bool { state.ready && state.pendingID == nil && state.modelID == model.runtimeID }

    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader(L10n.text(sourceLibrary ? "原作片段库 · " : "角色表现 · ") + model.name,backID:"closeCharacterPerformance") {
                Button { onReset("") } label: {
                    Label("全部默认",systemImage:"arrow.counterclockwise")
                        .font(.system(size:11,weight:.medium))
                        .foregroundStyle(Theme.secondary).frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!canSelect)
                    .accessibilityLabel("全部恢复默认").accessibilityIdentifier("performanceReset")
            }
            if let onOpenPreview {
                HStack(spacing:10) {
                    Text("已显示完整目录，进入角色会话后可手动预览。").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    Spacer(minLength:0)
                    Button("进入预览",action:onOpenPreview).font(.system(size:11,weight:.medium)).accessibilityIdentifier("developerOpenConversation")
                }.padding(.horizontal,18).padding(.bottom,8)
            } else if !state.ready {
                HStack(spacing:7) {ProgressView().controlSize(.mini);Text("正在同步角色表现…").font(.system(size:11)).foregroundStyle(Theme.secondary)}.padding(.bottom,8)
            }
            ScrollView(.horizontal) {
                HStack(spacing:6) {
                    ForEach(groups) { group in
                        Button {
                            withAnimation(.easeInOut(duration:reduceMotion ? 0.1 : 0.22)) { selectedGroup = group.id }
                        } label: {
                            Label(group.label,systemImage:group.resolvedSymbol)
                                .font(.system(size:12,weight:currentGroup == group.id ? .semibold : .regular))
                                .padding(.horizontal,11).frame(height:28)
                                .foregroundStyle(currentGroup == group.id ? Theme.ink : Theme.secondary)
                                .background(currentGroup == group.id ? Theme.accent.opacity(0.16) : Theme.surface.opacity(0.38),in:Capsule())
                                .overlay(Capsule().stroke(Theme.line.opacity(currentGroup == group.id ? 0.6 : 0.15),lineWidth:0.6))
                                .frame(minHeight:44)
                        }.buttonStyle(.plain).accessibilityIdentifier("performanceGroup-"+group.id)
                            .accessibilityAddTraits(currentGroup == group.id ? .isSelected : [])
                    }
                }.padding(.horizontal,18)
            }.scrollIndicators(.hidden).padding(.bottom,4).accessibilityIdentifier("performanceGroups")
            if sourceLibrary {
                HStack(spacing:8) {
                    Image(systemName:"magnifyingglass").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    TextField("搜索原作片段",text:$search).font(.system(size:12)).autocorrectionDisabled()
                        .accessibilityIdentifier("sourceMotionSearch")
                    Text("\(options.count)").font(.system(size:10,design:.monospaced)).foregroundStyle(Theme.secondary)
                }.padding(.horizontal,12).frame(height:32)
                    .background(Theme.surface.opacity(0.45),in:Capsule()).padding(.horizontal,18).padding(.bottom,8)
            }
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:138),spacing:7)],spacing:7) {
                    defaultButton
                    ForEach(options) { option in
                        if let control=option.control, control.kind == "slider" {
                            AvatarControlSlider(option:option,control:control,confirmed:state.controlValues[option.id],enabled:canSelect,onAdjust:onAdjust)
                        } else { optionButton(option) }
                    }
                }.padding(.horizontal,18).padding(.bottom,12)
            }.id(currentGroup).scrollIndicators(.hidden).accessibilityIdentifier("performanceOptions")
            if let error = state.error {
                Text(LocalizedStringKey(error)).font(.system(size:11)).foregroundStyle(Theme.peach)
                    .padding(.horizontal,18).padding(.bottom,12).accessibilityIdentifier("performanceError")
            }
        }.softPanelPageSurface().foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            // A root identifier propagates into the header and ScrollViews on iOS,
            // replacing their explicit identifiers. Keep identifiers on controls only.
            .onAppear { onVisibilityChanged(true) }
            .onDisappear { onVisibilityChanged(false) }
    }

    private var defaultButton: some View {
        let selected = state.ready && profile.isDefault(group:currentGroup,selections:state.selections)
        let pending = state.pendingOption == currentGroup
        let label = ["expression":"默认表情","pose":"默认待机","hands":"默认手势",
                     "ears":"默认耳朵","tail":"默认尾巴","appearance":"默认穿搭"][currentGroup] ?? "默认"
        return Button { onReset(currentGroup) } label: {
            HStack(spacing:7) {
                Image(systemName:"arrow.counterclockwise").font(.system(size:11,weight:.medium))
                    .foregroundStyle(Theme.secondary)
                Text(LocalizedStringKey(label)).font(.system(size:12,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading)
                if pending { ProgressView().controlSize(.mini).frame(width:17) }
                else {
                    Image(systemName:selected ? "checkmark" : "circle.dotted")
                        .font(.system(size:12,weight:.medium))
                        .foregroundStyle(selected ? Theme.accent : Theme.secondary.opacity(0.6)).frame(width:17)
                }
            }.padding(.horizontal,11).frame(minHeight:46)
                .background(selected ? Theme.accent.opacity(0.12) : Theme.surface.opacity(0.56),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(Theme.accent.opacity(selected ? 0.35 : 0.12),lineWidth:0.6))
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).disabled(!canSelect)
            .accessibilityIdentifier("performanceDefault-"+currentGroup)
            .accessibilityValue(pending ? "等待回应" : (selected ? "已选择" : "未选择"))
            .accessibilityHint("只恢复当前分类，保留其他表现和角色位置")
    }

    private func optionButton(_ option: CharacterPerformanceProfile.Option) -> some View {
        let selected = state.selections.contains(option.id)
        let pending = state.pendingOption == option.id
        return Button { onSelect(option.id,option.isToggle ? !selected : true) } label: {
            HStack(spacing:7) {
                VStack(alignment:.leading,spacing:2) {
                    Text(option.label).font(.system(size:12,weight:.medium)).lineLimit(2)
                        .frame(maxWidth:.infinity,alignment:.leading)
                    if option.id.hasPrefix("source-motion-") {
                        Text((option.duration ?? 0)<=0.05 ? "原作姿态 · 可恢复" : option.loop == true ? "原作循环 · 可恢复" : "原作片段 · 播放后恢复")
                            .font(.system(size:9)).foregroundStyle(Theme.secondary)
                        if option.description?.contains("部分通道") == true {
                            Text("部分通道适配").font(.system(size:9)).foregroundStyle(Theme.peach.opacity(0.8))
                        }
                    } else if option.kind == "motion" {
                        Text(option.loop == true ? "循环 · 可恢复" : "播放后恢复")
                            .font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }
                }
                if pending { ProgressView().controlSize(.mini).frame(width:17) }
                else {
                    Image(systemName:option.isToggle ? (selected ? "checkmark.circle.fill" : "circle") :
                            (selected ? "checkmark" : (option.kind == "motion" ? "play.fill" : "sparkle")))
                        .font(.system(size:12,weight:.medium)).foregroundStyle(selected ? Theme.accent : Theme.secondary.opacity(0.6))
                        .frame(width:17)
                }
            }.padding(.horizontal,11).frame(minHeight:46)
                .background(selected ? Theme.accent.opacity(0.12) : Theme.surface.opacity(0.56),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(Theme.accent.opacity(selected ? 0.35 : 0.06),lineWidth:0.6))
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).disabled(!canSelect)
            .accessibilityIdentifier("performanceOption-"+option.id)
            .accessibilityValue(pending ? "等待回应" : (selected ? "已选择" : "未选择"))
            .accessibilityHint(option.description ?? "")
    }
}

private struct AvatarControlSlider: View {
    let option: CharacterPerformanceProfile.Option
    let control: CharacterPerformanceProfile.Option.Control
    let confirmed: Double?
    let enabled: Bool
    let onAdjust: (String,Double) -> Void
    @State private var value: Double = 0
    @State private var editing = false
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(option.label).font(.system(size:12,weight:.medium)).lineLimit(2)
            Slider(value:Binding(get:{value},set:{ value=$0; onAdjust(option.id,$0) }),in:0...1,onEditingChanged:{editing=$0})
                .accessibilityIdentifier("performanceSlider-"+option.id)
        }.padding(11).background(Theme.surface.opacity(0.56),in:RoundedRectangle(cornerRadius:12))
            .disabled(!enabled)
            .onAppear {value=confirmed ?? min(1,max(0,(control.initial-control.minimum)/max(0.0001,control.maximum-control.minimum)))}
            .onChange(of:confirmed) { _,new in if !editing,let new {value=new} }
    }
}

#endif
