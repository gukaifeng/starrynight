import SwiftUI

/// One compact dock for the live scene. Only the position instructions pass
/// touches through; tabs, reset and both settings pages own their touches.
struct CharacterViewEditorPanel: View {
    let editor:CharacterViewEditor
    let session:CompanionSession
    var onSection:(CharacterViewEditor.Section)->Void
    var onReset:()->Void
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:2) {
                ForEach(CharacterViewEditor.Section.allCases,id:\.self) {section in
                    Button {
                        withAnimation(.easeInOut(duration:reduceMotion ? 0.15 : 0.25)) {onSection(section)}
                    } label: {
                        HStack(spacing:5) {
                            Image(systemName:section.symbol).font(.system(size:11))
                            Text(section.title).font(.system(size:12,weight:.medium))
                        }.foregroundStyle(Theme.ink.opacity(editor.section == section ? 0.95 : 0.48))
                            .frame(maxWidth:.infinity).frame(height:44)
                            .background { Capsule().fill(Theme.ink.opacity(editor.section == section ? 0.08 : 0)).frame(height:30) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("conversationSetting-"+section.rawValue)
                        .accessibilityAddTraits(editor.section == section ? .isSelected : [])
                }
            }.padding(.horizontal,7).padding(.top,4)
            Rectangle().fill(Theme.ink.opacity(0.08)).frame(height:0.5).padding(.horizontal,15)
            Group {
                switch editor.section {
                case .position:
                    VStack(alignment:.leading,spacing:7) {
                        Text("轻触角色，自在取景").font(.system(size:12,weight:.medium)).padding(.trailing,92)
                        Text("单指旋转 · 双指缩放或移动").font(.system(size:11)).foregroundStyle(Theme.ink.opacity(0.66))
                        Text(editor.status.isEmpty ? "自动记住 · 右上角轻点收起" : editor.status)
                            .font(.system(size:10)).foregroundStyle(Theme.ink.opacity(0.44)).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,13)
                        .overlay(alignment:.topTrailing) {
                            Button(action:onReset) {
                                Label("恢复默认",systemImage:"arrow.counterclockwise")
                                    .font(.system(size:11,weight:.medium)).foregroundStyle(Theme.ink.opacity(0.82))
                                    .frame(width:98,height:44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("resetCharacterView")
                                .offset(x:7)
                        }
                case .sound: ConversationSoundControls(session:session).padding(.top,5)
                case .atmosphere: atmosphere.padding(.top,10)
                }
            }.padding(.horizontal,15).frame(maxWidth:.infinity,alignment:.topLeading)
                .id(editor.section).transition(.opacity)
            Spacer(minLength:0)
        }
            .frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(Theme.ink)
            .modifier(CharacterViewGlass(opaque:opaque))
            .accessibilityElement(children:.contain).accessibilityIdentifier("conversationSettingsPanel")
    }
    private var atmosphere:some View {
        VStack(spacing:2) {
            HStack {
                Text("氛围效果").font(.system(size:12,weight:.medium))
                Spacer()
                Text(AtmosphereBlend.levelNames[session.record.profile.resolvedAtmosphereLevel])
                    .font(.system(size:11)).foregroundStyle(Theme.accent)
            }
            AtmosphereLevelSlider(level:Binding(get:{session.record.profile.resolvedAtmosphereLevel},set:{value in
                session.store.update(session.model.id) {$0.profile.atmosphereLevel=value;$0.profile.atmosphereEnabled=value>0}
            })).frame(height:38)
            HStack {Text("关闭");Spacer();Text("绚烂")}.font(.system(size:10)).foregroundStyle(Theme.secondary)
        }.tint(Theme.accent)
    }
}
private struct CharacterViewGlass:ViewModifier {
    let opaque:Bool
    @ViewBuilder func body(content:Content) -> some View {
        if opaque { content.background(Theme.surface,in:RoundedRectangle(cornerRadius:20)) }
        else if #available(iOS 26.0,*) {
            content.glassEffect(.regular.tint(Theme.background.opacity(0.10)),in:RoundedRectangle(cornerRadius:20))
        } else {
            content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20))
                .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.white.opacity(0.13),lineWidth:0.6))
        }
    }
}
