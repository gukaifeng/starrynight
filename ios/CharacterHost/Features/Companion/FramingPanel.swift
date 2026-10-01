import SwiftUI

struct FramingPanel: View {
    @State var draft: CharacterFraming
    var onPreview: (CharacterFraming) -> Void
    var onSave: (CharacterFraming) -> String?
    @Environment(\.softPanelCloseRequest) private var close
    @State private var error: String?
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("角色取景",backID:"closeFramingButton")
            ScrollView {
              VStack(alignment:.leading,spacing:20) {
                Picker("显示范围",selection:$draft.shot) {
                    Text("对话近景").tag("conversation")
                    Text("全身互动").tag("full")
                }.pickerStyle(.segmented).accessibilityIdentifier("framingShotPicker")
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("角色大小"); Spacer(); Text("\(Int((draft.size*100).rounded()))%").monospacedDigit().accessibilityIdentifier("framingSizeValue") }
                    Slider(value:$draft.size,in:0.9...1.1,step:0.01).accessibilityLabel("角色大小").accessibilityValue("\(Int((draft.size*100).rounded()))%")
                        .accessibilityIdentifier("framingSizeSlider")
                    HStack {
                        Button("90%") { draft.size = 0.9 }.accessibilityIdentifier("framingSizeMin")
                        Spacer()
                        Button("110%") { draft.size = 1.1 }.accessibilityIdentifier("framingSizeMax")
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("左右朝向"); Spacer(); Text(angleLabel).monospacedDigit().accessibilityIdentifier("framingAngleValue") }
                    Slider(value:$draft.angle,in:-20...20,step:1).accessibilityLabel("左右朝向").accessibilityValue(angleLabel)
                        .accessibilityIdentifier("framingAngleSlider")
                    HStack {
                        Button("左 20°") { draft.angle = -20 }.accessibilityIdentifier("framingAngleLeft")
                        Spacer()
                        Button("正面") { draft.angle = 0 }.accessibilityIdentifier("framingAngleFront")
                        Spacer()
                        Button("右 20°") { draft.angle = 20 }.accessibilityIdentifier("framingAngleRight")
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
                HStack(alignment:.top,spacing:16) {
                    Text("在定制首页关闭“锁定角色位置”后，可轻拖角色转向、双指缩放，松手自动记住。这里可随时精细调整或恢复推荐。").font(.caption).foregroundStyle(Theme.secondary)
                    Spacer(minLength:0)
                    Button("恢复推荐") { draft = .recommended }.font(.subheadline).fixedSize().accessibilityIdentifier("restoreFramingButton")
                }
                if let error { Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("framingSaveError") }
              }.padding(.horizontal,22).padding(.bottom,28)
            }.scrollIndicators(.hidden)
        }.scrollIndicators(.hidden).foregroundStyle(Theme.ink).tint(Theme.accent)
        .softPanelPageSurface()
        .onAppear { close?.beforeClose = { error = onSave(draft.normalized); return error == nil } }
        .onDisappear { close?.beforeClose = nil }
        .onChange(of:draft) { _, value in onPreview(value.normalized) }
        .accessibilityElement(children:.contain).accessibilityIdentifier("framingPanel")
    }
    private var angleLabel: String { abs(draft.angle) < 0.5 ? "正面" : String(format:"%@ %.0f°",draft.angle < 0 ? "左" : "右",abs(draft.angle)) }
}
