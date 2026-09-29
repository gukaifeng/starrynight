import SwiftUI

/// Presentation only. UIKit routes every point through to the model except the
/// native reset button laid over the reserved top-right 88 × 44 pt area.
struct CharacterViewEditorPanel: View {
    let editor:CharacterViewEditor
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text("调整位置").font(.system(size:13,weight:.medium))
                Spacer(minLength:92)
            }.frame(height:30)
            Text("单指旋转 · 双指缩放或移动")
                .font(.system(size:11)).foregroundStyle(Theme.ink.opacity(0.66))
            Text(editor.status.isEmpty ? "自动记住 · 右上角轻点结束" : editor.status)
                .font(.system(size:10)).foregroundStyle(Theme.ink.opacity(0.44)).lineLimit(1)
        }.padding(.horizontal,15).padding(.top,6).padding(.bottom,12)
            .frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(Theme.ink)
            .modifier(CharacterViewGlass(opaque:opaque)).allowsHitTesting(false)
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
