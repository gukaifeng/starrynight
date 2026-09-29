import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, messages, create, discover, mine
    var id:String { rawValue }
    var title:String { switch self { case .home:"对话"; case .messages:"消息"; case .create:"创建"; case .discover:"发现"; case .mine:"我的" } }
    var symbol:String { switch self { case .home:"bubble.left.and.text.bubble.right"; case .messages:"bubble.left.and.bubble.right"; case .create:"plus"; case .discover:"sparkle.magnifyingglass"; case .mine:"person.crop.circle" } }
}
struct AppDock: View {
    let selection:AppTab
    var bottomInset:CGFloat = 0
    var onSelect:(AppTab)->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var glow = false
    var body:some View {
        HStack(spacing:0) {
            ForEach(AppTab.allCases) { tab in
                Button { onSelect(tab) } label: {
                    ZStack {
                        if tab == .create {
                            ZStack {
                                Circle().fill(Theme.accent.opacity(glow ? 0.22 : 0.10)).blur(radius:6).frame(width:48,height:48)
                                Ellipse().stroke(AngularGradient(colors:Theme.spectrum + [Theme.accent],center:.center),lineWidth:1)
                                    .frame(width:46,height:31).rotationEffect(.degrees(-28))
                                Image(systemName:"plus").font(.system(size:24,weight:.light)).foregroundStyle(Theme.ink)
                            }.frame(width:48,height:48)
                        } else {
                            Text(tab.title).font(.system(size:14,weight:selection == tab ? .semibold : .regular)).tracking(1)
                        }
                    }.foregroundStyle(selection == tab ? Theme.accent : Theme.secondary)
                        .frame(maxWidth:.infinity,minHeight:58).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("tab-"+tab.rawValue)
                    .accessibilityLabel(tab == .create ? "创建角色" : tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }.padding(.horizontal,12).frame(height:62).frame(maxWidth:760).frame(maxWidth:.infinity).padding(.bottom,bottomInset)
            .background {
                Theme.background.opacity(reduceTransparency ? 1 : 0.94)
                    .overlay(alignment:.top) { Rectangle().fill(Theme.line.opacity(0.75)).frame(height:0.5) }
                    .ignoresSafeArea(edges:.bottom)
            }
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration:3.4).repeatForever(autoreverses:true)) { glow = true } } }
    }
}
struct NightBackdrop: View {
    var body:some View {
        GeometryReader { geometry in
            ZStack {
                Theme.background
                RadialGradient(colors:[Theme.spectrum[0].opacity(0.12),.clear],center:.topTrailing,startRadius:0,endRadius:geometry.size.width*0.9)
                RadialGradient(colors:[Theme.peach.opacity(0.10),.clear],center:.init(x:0,y:0.5),startRadius:0,endRadius:geometry.size.width*0.75)
                RadialGradient(colors:[Theme.spectrum.last!.opacity(0.07),.clear],center:.bottomTrailing,startRadius:0,endRadius:geometry.size.width)
            }
        }.ignoresSafeArea()
    }
}
struct NightHeader: View {
    let title:String
    let subtitle:String
    var body:some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:7) {
                Text(title).font(.system(size:27,weight:.semibold,design:.rounded)).tracking(2)
                Text(subtitle).font(.system(size:12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Image("BrandMark").resizable().frame(width:43,height:43).clipShape(.rect(cornerRadius:13)).accessibilityHidden(true)
        }.padding(.horizontal,24).padding(.top,16).padding(.bottom,16)
    }
}
struct NightEmptyState: View {
    let symbol:String
    let title:String
    let detail:String
    let actionTitle:String
    var action:()->Void
    var body:some View {
        GeometryReader { geometry in
        VStack(spacing:18) {
            Image(systemName:symbol).font(.system(size:42,weight:.ultraLight)).foregroundStyle(Theme.accent)
                .frame(width:88,height:88).background(Theme.accent.opacity(0.08),in:Circle())
            Text(title).font(.title3.weight(.medium))
            Text(detail).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button(actionTitle,action:action).buttonStyle(NightPrimaryButton()).accessibilityIdentifier("emptyStateAction")
        }.padding(28).frame(maxWidth:480).frame(maxWidth:.infinity,maxHeight:.infinity)
            .offset(y:geometry.size.height > 400 ? -42 : 0)
        }
    }
}
struct NightPrimaryButton: ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:15,weight:.semibold)).padding(.horizontal,24).frame(minHeight:48)
            .foregroundStyle(Theme.background).background(Theme.gradient,in:Capsule()).opacity(configuration.isPressed ? 0.75 : 1)
    }
}
