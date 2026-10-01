import SwiftUI

/// A deliberate fade and small rise, instead of the system alert's fast pop.
/// Kept in the page overlay so the revealed row doesn't reset underneath it.
struct ConversationDeleteConfirmation: View {
    let name: String
    let onCancel: () -> Void
    let onDelete: () -> Void
    @State private var visible = false
    @State private var closing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    private var animation: Animation { .easeInOut(duration:reduceMotion ? 0.2 : 0.46) }
    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.58 : 0).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { dismiss(onCancel) }.accessibilityHidden(true)
            VStack(alignment:.leading,spacing:18) {
                Text("删除对话和记忆？").font(.system(size:18,weight:.semibold))
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                Text("将永久清空你与「\(name)」的全部聊天记录、记忆和相处进度，无法撤销。订阅与个人设置会保留。再次进入将重新认识。")
                    .font(.system(size:14)).lineSpacing(5).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:12) {
                    Button("取消") { dismiss(onCancel) }.frame(maxWidth:.infinity,minHeight:44)
                        .background(Theme.card,in:Capsule()).accessibilityIdentifier("cancelConversationDeletion")
                    Button("删除全部",role:.destructive) { dismiss(onDelete) }.frame(maxWidth:.infinity,minHeight:44)
                        .foregroundStyle(Color(hex:0xF1A2AD)).background(Color(hex:0xC54659).opacity(0.2),in:Capsule())
                        .accessibilityIdentifier("confirmConversationDeletion")
                }.font(.system(size:14,weight:.medium)).buttonStyle(.plain)
            }.padding(24).frame(maxWidth:360).background(Theme.surface,in:RoundedRectangle(cornerRadius:28))
                .overlay(RoundedRectangle(cornerRadius:28).stroke(Theme.line.opacity(0.45),lineWidth:0.5))
                .padding(.horizontal,24).opacity(visible ? 1 : 0).offset(y:visible || reduceMotion ? 0 : 14)
        }.foregroundStyle(Theme.ink).disabled(closing)
            .accessibilityElement(children:.contain).accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("conversationDeleteConfirmation")
            .onAppear { withAnimation(animation) {visible=true};titleFocused=true }
            .accessibilityAction(.escape) { dismiss(onCancel) }
    }
    private func dismiss(_ completion: @escaping () -> Void) {
        guard !closing else {return};closing=true
        withAnimation(animation,completionCriteria:.logicallyComplete) {visible=false} completion: {completion()}
    }
}
