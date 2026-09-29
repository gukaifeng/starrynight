import SwiftUI

struct CharacterHomeCard: View {
    let model: ModelDescriptor
    let profile: CharacterProfile
    let portrait: UIImage?
    let size: CGSize
    let index: Int
    let hasConversation: Bool
    let isActive: Bool
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var floating = false
    private var compact: Bool { size.height < 260 }
    private var horizontal: Bool { size.height < 185 }
    private var tint: Color {
        if profile.accent == "鸢紫" { return Color(red:0.898,green:0.875,blue:0.941) }
        if profile.accent == "暖金" { return Color(red:0.949,green:0.875,blue:0.820) }
        return [Color(red:0.949,green:0.875,blue:0.820),Color(red:0.871,green:0.918,blue:0.875),
                Color(red:0.851,green:0.906,blue:0.929),Color(red:0.898,green:0.875,blue:0.941)][index%4]
    }
    private var invitation: String {
        switch model.id {
        case "real-woman": "今天的心事，\n慢慢说给我听。"
        case "studio-robot": "开心的小事，\n也想和你一起收集。"
        case "hatsune-miku": "把今天的心情，\n变成我们的旋律。"
        case "sample-robot": "来聊一会儿吧，\n我在认真听。"
        default: model.display.invitation
        }
    }
    private var shouldFloat: Bool { isActive && !reduceMotion && scenePhase == .active }
    var body: some View {
        Group {
            if horizontal {
                HStack(spacing:12) {
                    avatar(side:min(74,size.height-28))
                    VStack(alignment:.leading,spacing:4) { identity; chatLink }
                }.padding(14)
            } else {
                VStack(spacing:compact ? 6 : 8) {
                    avatar(side:min(size.width-44,compact ? 78 : min(154,size.height*0.34)))
                    identity
                    if !compact {
                        Text(invitation).font(.system(size:size.width > 250 ? 14 : 12))
                            .foregroundStyle(Theme.secondary).lineSpacing(4).multilineTextAlignment(.center)
                            .lineLimit(2).minimumScaleFactor(0.85).accessibilityHidden(true)
                    }
                    Spacer(minLength:0)
                    chatLink
                }.padding(.horizontal,compact ? 12 : 16).padding(.vertical,compact ? 10 : 14)
            }
        }
        .frame(width:size.width,height:size.height)
        .background {
            RoundedRectangle(cornerRadius:26,style:.continuous)
                .fill(LinearGradient(colors:[tint.opacity(0.78),.white.opacity(0.91)],startPoint:.topLeading,endPoint:.bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius:26,style:.continuous).stroke(.white.opacity(0.85),lineWidth:1))
        .shadow(color:Theme.ink.opacity(0.055),radius:12,y:6)
        .onAppear { setFloating() }
        .onChange(of:shouldFloat) { _,_ in setFloating() }
    }
    private func setFloating() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { floating = false }
        if shouldFloat {
            withAnimation(.easeInOut(duration:3.3+Double(index%4)*0.35).repeatForever(autoreverses:true)) { floating = true }
        }
    }
    private func avatar(side:CGFloat) -> some View {
        Button(action:onOpen) {
            ZStack {
                let shape = Circle()
                shape.fill(tint).rotationEffect(.degrees(index%2==0 ? -8 : 8)).offset(x:index%2==0 ? -4 : 4,y:3)
                Image(uiImage:portrait ?? UIImage(named:model.thumbnail+"Portrait") ?? UIImage(named:model.thumbnail) ?? UIImage())
                    .resizable().scaledToFill().frame(width:side,height:side).clipShape(shape)
                    .overlay(shape.stroke(.white.opacity(0.92),lineWidth:2))
                    .shadow(color:Theme.ink.opacity(0.08),radius:8,y:5)
                    .rotationEffect(.degrees(shouldFloat ? (floating ? 1.2 : -1.2) : 0))
                    .offset(y:shouldFloat && floating ? -2 : 1)
            }.frame(width:side,height:side).contentShape(Rectangle())
        }.buttonStyle(CharacterCardPressStyle()).accessibilityLabel("和"+profile.name+"聊天")
            .accessibilityIdentifier(model.cardIdentifier)
#if DEBUG
            .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? (portrait == nil ? "bundled" : "custom:"+CharacterPortraitStore.key(model:model,profile:profile)) : "")
#endif
    }
    private var identity: some View {
        Button(action:onOpen) {
            VStack(spacing:compact ? 2 : 5) {
                Text(profile.name).font(.system(size:compact ? 18 : size.width>250 ? 24 : 20,weight:.medium,design:.rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                if !compact && size.height > 300 {
                    Text(profile.personality+" · "+profile.tone).font(.system(size:10,weight:.medium))
                        .tracking(1).foregroundStyle(Theme.secondary.opacity(0.8)).lineLimit(1)
                }
            }.frame(maxWidth:.infinity).contentShape(Rectangle())
        }.buttonStyle(CharacterCardPressStyle()).accessibilityIdentifier("intro-"+model.id)
            .accessibilityLabel(profile.name+"，"+invitation.replacingOccurrences(of:"\n",with:""))
    }
    private var chatLink: some View {
        Button(action:onOpen) {
            HStack(spacing:5) {
                Text(hasConversation ? "继续聊" : "聊一会儿").font(.system(size:12,weight:.medium))
                Spacer(minLength:2)
                Image(systemName:"arrow.up.right").font(.system(size:11,weight:.medium))
                    .frame(width:26,height:26).background(Theme.surface.opacity(0.72),in:Circle())
            }.padding(.horizontal,12).frame(height:44)
                .background(Theme.surface.opacity(0.45),in:RoundedRectangle(cornerRadius:15))
                .contentShape(Rectangle())
        }.buttonStyle(CharacterCardPressStyle()).accessibilityLabel("和"+profile.name+"聊天")
            .accessibilityIdentifier("chat-"+model.id)
    }
}
private struct CharacterCardPressStyle: PrimitiveButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        CharacterCardPressLabel(content:configuration.label,action:configuration.trigger)
    }
}
private struct CharacterCardPressLabel<Content:View>: View {
    let content: Content
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    var body: some View {
        content.scaleEffect(pressed && !reduceMotion ? 0.965 : 1).opacity(pressed ? 0.8 : 1)
            .animation(.easeOut(duration:0.18),value:pressed)
            // A vertical brush must cancel a tap as well as a horizontal page swipe.
            .onTapGesture {
                pressed = true
                action()
                Task { @MainActor in
                    try? await Task.sleep(for:.milliseconds(180))
                    pressed = false
                }
            }
            .accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
}
