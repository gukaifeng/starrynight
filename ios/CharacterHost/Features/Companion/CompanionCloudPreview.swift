import SwiftUI

enum CompanionCloudFeature:String,CaseIterable,Identifiable {
    case voice, vision, sync, community
    var id:String { rawValue }
    var title:String {
        switch self { case .voice:"实时语音"; case .vision:"看图聊天"; case .sync:"云端记忆"; case .community:"创作者社区" }
    }
    var subtitle:String {
        switch self {
        case .voice:"自然接话，随时打断"
        case .vision:"把眼前的世界分享给对方"
        case .sync:"换一台设备，也能接着聊"
        case .community:"发现故事，与创作者交流"
        }
    }
    var symbol:String {
        switch self { case .voice:"phone"; case .vision:"photo"; case .sync:"icloud"; case .community:"person.2" }
    }
    var capabilities:[String] {
        switch self {
        case .voice:["免手持接话与打断","字幕与口型同步","切到后台自动停麦"]
        case .vision:["选择照片，发送前确认","围绕图片接着聊天","可删除的图片记录"]
        case .sync:["对话、相处设定与已确认记忆","角色独立，账号间不可见","同步状态与删除控制"]
        case .community:["作品详情、标签与搜索","评论、收藏与作者主页","私有创作与审核发布"]
        }
    }
}

/// Explicitly unavailable: no SDK connection, microphone request, upload or fake success.
struct CompanionCloudPreview:View {
    let feature:CompanionCloudFeature
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader(feature.title,backID:"closeCloudPreview") {
                Text("界面预览").font(.system(size:10)).foregroundStyle(Theme.peach)
            }
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    ZStack {
                        RoundedRectangle(cornerRadius:25).fill(Theme.surface.opacity(0.65))
                        VStack(spacing:17) {
                            Image(systemName:feature.symbol).font(.system(size:38,weight:.ultraLight)).foregroundStyle(Theme.gradient)
                                .frame(width:94,height:94).overlay(Circle().stroke(Theme.accent.opacity(0.14),lineWidth:0.7))
                            Text(feature.subtitle).font(.system(size:16,weight:.medium))
                            if feature == .voice {
                                HStack(spacing:30) {
                                    Image(systemName:"mic.slash");Text("未连接").font(.system(size:12));Image(systemName:"phone.down")
                                }.foregroundStyle(Theme.secondary)
                            }
                        }.padding(24)
                    }.frame(height:215)
                    ForEach(feature.capabilities,id:\.self) { item in
                        HStack(spacing:12) {
                            Circle().fill(Theme.peach.opacity(0.6)).frame(width:4,height:4)
                            Text(item).font(.system(size:14)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Button("服务尚未开通") {}.buttonStyle(NightPrimaryButton()).disabled(true)
                        .accessibilityIdentifier("cloudUnavailableButton")
                    Text("当前仅展示玩法，尚未连接云端服务。不会开启麦克风、上传照片或同步你的记录。现有本机聊天和语音仍可正常使用。")
                        .font(.system(size:12)).lineSpacing(4).foregroundStyle(Theme.secondary)
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden)
        }.softPanelPageSurface().foregroundStyle(Theme.ink).tint(Theme.accent)
            .accessibilityElement(children:.contain).accessibilityIdentifier("cloudPreview-"+feature.rawValue)
    }
}
