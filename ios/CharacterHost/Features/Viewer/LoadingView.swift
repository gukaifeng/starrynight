import SwiftUI

/// A quiet orbital animation on the same opaque night canvas as the app. It stays
/// beneath the live-window crossfade until the engine has completed its renders.
struct CharacterArrivalView: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var orbiting = false
    var body: some View {
        VStack(spacing:27) {
            ZStack {
                Circle().fill(Theme.accent.opacity(breathing ? 0.08 : 0.035))
                    .frame(width:112,height:112).blur(radius:25)
                    .scaleEffect(breathing ? 1.14 : 0.92)
                    .animation(reduceMotion ? nil : .easeInOut(duration:2.2).repeatForever(autoreverses:true),value:breathing)
                Circle().stroke(Theme.ink.opacity(0.06),lineWidth:0.6).frame(width:152,height:152)
                    .rotation3DEffect(.degrees(64),axis:(x:1,y:0,z:0)).rotationEffect(.degrees(-28))
                Circle().trim(from:0.03,to:0.38)
                    .stroke(AngularGradient(colors:[Theme.ink.opacity(0),Theme.ink.opacity(0.48),Theme.ink.opacity(0.08)],center:.center),style:StrokeStyle(lineWidth:1,lineCap:.round))
                    .frame(width:152,height:152).rotationEffect(.degrees(orbiting ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration:4.8).repeatForever(autoreverses:false),value:orbiting)
                    .rotation3DEffect(.degrees(64),axis:(x:1,y:0,z:0)).rotationEffect(.degrees(-28))
                Image("BrandMark").resizable().scaledToFit().frame(width:62,height:62)
                    .opacity(breathing ? 0.96 : 0.58).scaleEffect(breathing ? 1.025 : 0.975)
                    .animation(reduceMotion ? nil : .easeInOut(duration:2.2).repeatForever(autoreverses:true),value:breathing)
                Circle().fill(Theme.ink.opacity(0.6)).frame(width:2.5,height:2.5).offset(x:57,y:-42)
                Circle().fill(Theme.ink.opacity(0.25)).frame(width:1.5,height:1.5).offset(x:-61,y:26)
            }.frame(width:180,height:154).accessibilityHidden(true)
            VStack(spacing:11) {
                Text("正在与\(name)相见").font(.system(size:15,weight:.medium)).tracking(1.5)
                Text("让星光，慢慢靠近").font(.system(size:11,weight:.regular)).tracking(3)
                    .foregroundStyle(Theme.secondary.opacity(0.7))
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).offset(y:-24)
            .accessibilityElement(children:.combine).accessibilityIdentifier("characterArrival")
            .onAppear { breathing = !reduceMotion; orbiting = !reduceMotion }
            .onChange(of:reduceMotion) { breathing = !reduceMotion; orbiting = !reduceMotion }
    }
}

/// A small card laid over the selected portrait; the home and role stay visible.
struct LoadingView: View {
    var failed: Bool
    var errorMessage: String
    var onCancel: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(alignment:.center,spacing:14) {
            Group {
                if failed { Image(systemName:"exclamationmark.triangle").font(.title2) }
                else { ProgressView().tint(Theme.accent) }
            }.frame(width:26).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:5) {
                Text(failed ? "暂时无法打开角色" : "正在准备角色")
                    .font(.subheadline.weight(.semibold))
                Text(failed ? errorMessage : "马上就能见面了")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Button(action:onCancel) {
                Image(systemName:"xmark").font(.system(size:14,weight:.medium)).frame(width:44,height:44)
                    .background(Theme.card.opacity(0.7),in:Circle())
            }.buttonStyle(.plain).accessibilityLabel(failed ? "返回角色选择" : "取消打开角色")
                .accessibilityIdentifier("cancelLoadingButton")
        }.padding(16).foregroundStyle(Theme.ink)
            .background(Theme.background.opacity(reduceTransparency ? 1 : 0.94),in:RoundedRectangle(cornerRadius:24))
            .overlay(RoundedRectangle(cornerRadius:24).stroke(Theme.line.opacity(0.8),lineWidth:1))
            .shadow(color:Theme.ink.opacity(0.08),radius:16,y:4)
            .accessibilityElement(children:.contain)
    }
}
