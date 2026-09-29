import SwiftUI

struct CharacterStudioPanel: View {
    @State var draft: CharacterStudio
    let customizable: Bool
    var environments: [EnvironmentDescriptor] = []
    var parameters: [CharacterParameter] = []
    var posture: PostureProfile? = nil
    var onPreview: (CharacterStudio) -> Void
    var onSave: (CharacterStudio) -> String?
    @State var tab = "face"
    @State private var environmentMode = "choose"
    @Environment(\.softPanelCloseRequest) private var close
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        panelContent
            .foregroundStyle(Theme.ink).tint(Theme.accent)
            .softPanelPageSurface()
            .animation(.easeInOut(duration:reduceMotion ? 0.18 : 0.28),value:tab)
            .animation(.easeInOut(duration:reduceMotion ? 0.18 : 0.28),value:environmentMode)
        .onAppear {
            close?.beforeClose = { error = onSave(draft.normalized); return error == nil }
        }
        .onDisappear { close?.beforeClose = nil }
            .onChange(of:draft) { (_:CharacterStudio, value:CharacterStudio) in onPreview(value.normalized) }
            .accessibilityElement(children:.contain).accessibilityIdentifier("characterStudioPanel")
    }
    private var panelContent: some View {
        VStack(spacing:0) {
            header
            VStack(spacing:14) {
                tabs
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        controls
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding(.bottom,16)
                }.scrollIndicators(.hidden)
                footer
            }.padding(.horizontal,22).padding(.bottom,12)
        }
    }
    private var header: some View {
        PanelPageHeader(customizable || !parameters.isEmpty ? "定制你的角色" : "布置角色空间",
                        subtitle:"每一点改变，都能实时看到",backID:"closeStudioButton")
    }
    @ViewBuilder private var tabs: some View {
            if customizable {
                Picker("定制项目",selection:$tab) {
                    Text("面容").tag("face"); Text("身形").tag("body")
                    Text("造型").tag("style"); Text("空间").tag("room")
                    if posture != nil { Text("姿势").tag("posture") }
                }.pickerStyle(.segmented).accessibilityIdentifier("studioTabs")
            }
            if !customizable && (!parameters.isEmpty || posture != nil) {
                Picker("定制项目",selection:$tab) { Text("造型").tag("face"); Text("空间").tag("room"); if posture != nil { Text("姿势").tag("posture") } }
                    .pickerStyle(.segmented).accessibilityIdentifier("studioTabs")
            }
    }
    @ViewBuilder private var controls: some View {
                    if tab == "posture", let posture {
                        PostureControls(preferences:Binding(get:{draft.posture ?? PosturePreferences()},set:{draft.posture=$0}),profile:posture)
                    }
                    else if !parameters.isEmpty && tab != "room" { packageControls }
                    else if !customizable || tab == "room" { roomControls }
                    else if tab == "face" { faceControls }
                    else if tab == "body" { bodyControls }
                    else { styleControls }
    }
    private var footer: some View {
        HStack {
            Text(customizable ? "成年女性 · 写实角色" : "背景和灯光会随角色保存")
                .font(.caption).foregroundStyle(Theme.secondary)
            Spacer()
            Button(tab == "room" || (!customizable && parameters.isEmpty) ? "重置当前空间" : "恢复推荐") {
                if tab == "posture" { var p=draft.posture ?? PosturePreferences();p.values[p.id]=nil;draft.posture=p }
                else if tab == "room" || (!customizable && parameters.isEmpty) { draft.resetEnvironment() } else { draft.resetAppearance() }
            }.font(.caption).frame(minHeight:40).accessibilityIdentifier("restoreStudioButton")
        }
    }
    private var packageControls: some View {
        VStack(alignment:.leading,spacing:16) {
            ForEach(parameters) { p in
                VStack(alignment:.leading,spacing:8) {
                    Text(p.label).font(.subheadline.weight(.medium))
                    let value = Binding<Double>(get:{ draft.parameters?[p.id] ?? p.initial },set:{
                        if draft.parameters == nil { draft.parameters = [:] }; draft.parameters?[p.id] = $0
                    })
                    if p.kind == "morph" { Slider(value:value,in:p.min...p.max).accessibilityIdentifier("parameter-" + p.id) }
                    else {
                        HStack {
                            ForEach(Array(p.options.enumerated()),id:\.offset) { option in
                                Button {
                                    value.wrappedValue = Double(option.offset)
                                } label: {
                                    Text(p.kind == "color" ? "色调 \(option.offset + 1)" : option.element)
                                        .font(.caption).padding(10).background(value.wrappedValue.rounded() == Double(option.offset) ? Theme.accent.opacity(0.2) : Theme.surface.opacity(0.5),in:Capsule())
                                }.accessibilityIdentifier("parameter-" + p.id + "-" + String(option.offset))
                                    .accessibilityAddTraits(value.wrappedValue.rounded() == Double(option.offset) ? .isSelected : [])
                            }
                        }
                    }
                }
            }
        }
    }
    private var faceControls: some View {
        VStack(spacing:16) {
            adjustment("脸型",low:"秀长",high:"柔圆",value:$draft.faceWidth,id:"faceWidth")
            adjustment("下颌",low:"柔和",high:"分明",value:$draft.jawShape,id:"jawShape")
            adjustment("眼型",low:"修长",high:"明亮",value:$draft.eyeSize,id:"eyeSize")
            adjustment("唇形",low:"轻薄",high:"丰润",value:$draft.mouthShape,id:"mouthShape")
            adjustment("鼻翼",low:"窄",high:"宽",value:$draft.noseWidth,id:"noseWidth")
        }
    }
    private var bodyControls: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("自然比例，由你慢慢调整").font(.subheadline.weight(.medium))
            adjustment("体态",low:"纤细",high:"饱满",value:$draft.bodyBuild,id:"bodyBuild")
            adjustment("腰胯",low:"平直",high:"曲线",value:$draft.bodyCurve,id:"bodyCurve")
            adjustment("身高",low:"偏矮",high:"偏高",value:$draft.height,id:"bodyHeight")
            Text("衣服会随身形一起调整。建议切到全身取景查看整体效果。")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var styleControls: some View {
        VStack(alignment:.leading,spacing:18) {
            choices("肤色",selection:$draft.skin,items:[("fair","浅肤"),("natural","自然"),("warm","暖棕"),("deep","深棕")])
            choices("眼睛",selection:$draft.eyes,items:[("brown","深棕"),("hazel","榛色"),("green","灰绿")])
            choices("发型",selection:$draft.hair,items:[("long","长发"),("bob","短发")])
            choices("发色",selection:$draft.hairColor,items:[("espresso","深棕"),("chestnut","栗色"),("black","乌黑")])
            choices("衣服",selection:$draft.clothing,items:[("ivory","暖白"),("sage","浅绿"),("rose","烟粉")])
        }
    }
    private var roomControls: some View {
        VStack(alignment:.leading,spacing:18) {
            Picker("空间设置",selection:$environmentMode) {
                Text("选择空间").tag("choose"); Text("布置与光影").tag("customize")
            }.pickerStyle(.segmented).accessibilityIdentifier("environmentMode")
            EnvironmentPicker(draft:$draft,environments:environments,customize:environmentMode == "customize")
            if environmentMode == "customize" {
            adjustment("光从哪边来",low:"左侧",high:"右侧",value:$draft.lightAngle,id:"lightAngle",range:-90...90)
            adjustment("光源高度",low:"低角度",high:"高角度",value:$draft.lightHeight,id:"lightHeight",range:20...75)
            adjustment("光线亮度",low:"柔和",high:"明亮",value:$draft.lightIntensity,id:"lightIntensity",range:0.6...1.5)
            adjustment("影子深浅",low:"浅",high:"深",value:$draft.shadow,id:"shadowStrength",range:0.15...1)
            Text("影子会随着光源转动，全身取景下更容易看清地面的变化。")
                .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
    private func adjustment(_ label: String,low: String,high: String,value: Binding<Double>,id: String,range: ClosedRange<Double> = 0...1) -> some View {
        VStack(spacing:5) {
            HStack { Text(label).font(.subheadline.weight(.medium)); Spacer(); Text(low + " · " + high).font(.caption).foregroundStyle(Theme.secondary) }
            Slider(value:value,in:range).accessibilityLabel(label).accessibilityIdentifier("studio-" + id)
        }
    }
    private func choices(_ label: String,selection: Binding<String>,items: [(String,String)]) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(label).font(.subheadline.weight(.medium))
            Picker(label,selection:selection) { ForEach(items,id:\.0) { item in Text(item.1).tag(item.0) } }
                .pickerStyle(.segmented).accessibilityIdentifier("studio-" + label)
        }
    }
}
