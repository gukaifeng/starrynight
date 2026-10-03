import SwiftUI
import WidgetKit

@main struct ConversationIslandBundle: WidgetBundle {
    var body:some Widget {ConversationIslandWidget()}
}

struct ConversationIslandWidget: Widget {
    var body:some WidgetConfiguration {
        ActivityConfiguration(for:ConversationActivityAttributes.self) { context in
            ConversationIslandCard(attributes:context.attributes,state:context.state,stale:context.isStale)
                .activityBackgroundTint(Color(red:0.045,green:0.052,blue:0.074))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(ConversationActivityAttributes.route(characterID:context.attributes.characterID,messageID:context.state.messageID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandAvatar(asset:context.attributes.avatarAsset,name:context.attributes.characterName,size:34)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandSignal(state:context.state,stale:context.isStale)
                        .frame(width:50,height:34)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment:.leading,spacing:3) {
                        IslandName(name:context.attributes.characterName,state:context.state,stale:context.isStale)
                        Text(ConversationIslandCopy.text(context.isStale ? "stale" : context.state.phase.rawValue,language:context.state.language))
                            .font(.system(size:11)).foregroundStyle(IslandPalette.moon.opacity(0.72)).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandFooter(attributes:context.attributes,state:context.state,stale:context.isStale)
                        .padding(.top,5)
                }
            } compactLeading: {
                IslandAvatar(asset:context.attributes.avatarAsset,name:context.attributes.characterName,size:24)
            } compactTrailing: {
                IslandSignal(state:context.state,stale:context.isStale,compact:true).frame(width:36)
            } minimal: {
                IslandAvatar(asset:context.attributes.avatarAsset,name:context.attributes.characterName,size:22)
            }
            .widgetURL(ConversationActivityAttributes.route(characterID:context.attributes.characterID,messageID:context.state.messageID))
            .keylineTint(IslandPalette.mint)
        }
    }
}

private enum IslandPalette {
    static let moon=Color(red:0.95,green:0.96,blue:0.99)
    static let mint=Color(red:0.65,green:0.89,blue:0.83)
    static let blush=Color(red:0.94,green:0.71,blue:0.76)
    static let glow=LinearGradient(colors:[mint,moon,blush],startPoint:.topLeading,endPoint:.bottomTrailing)
}
private struct IslandAvatar:View {
    let asset:String
    let name:String
    let size:CGFloat
    var body:some View {
        ZStack {
            Circle().fill(IslandPalette.glow.opacity(0.24))
            if let image=UIImage(named:asset) {
                Image(uiImage:image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1))).font(.system(size:size*0.46,weight:.medium)).foregroundStyle(IslandPalette.moon)
            }
        }.frame(width:size,height:size).clipShape(Circle())
            .overlay(Circle().stroke(IslandPalette.glow.opacity(0.7),lineWidth:0.7))
            .accessibilityLabel(name)
    }
}
private struct IslandSignal:View {
    let state:ConversationActivityAttributes.ContentState
    let stale:Bool
    var compact=false
    var body:some View {
        Group {
            if !stale,state.phase == .speaking,let start=state.playbackStart,let end=state.playbackEnd,end>start {
                Text(timerInterval:start...end,countsDown:true).monospacedDigit()
                    .font(.system(size:compact ? 11 : 13,weight:.medium)).multilineTextAlignment(.trailing)
            } else {
                Image(systemName:stale ? "moon.stars" : ConversationIslandCopy.symbol(state))
                    .font(.system(size:compact ? 12 : 16,weight:.medium)).contentTransition(.symbolEffect(.replace))
            }
        }.foregroundStyle(IslandPalette.glow)
            .accessibilityLabel(ConversationIslandCopy.text(stale ? "stale" : state.phase.rawValue,language:state.language))
    }
}
private struct IslandName:View {
    let name:String
    let state:ConversationActivityAttributes.ContentState
    let stale:Bool
    var body:some View {
        HStack(spacing:6) {
            Text(name).font(.system(size:15,weight:.semibold)).lineLimit(1)
            if !stale,state.phase == .speaking {
                Image(systemName:ConversationIslandCopy.symbol(state))
                    .font(.system(size:10,weight:.medium)).foregroundStyle(IslandPalette.glow)
                    .contentTransition(.symbolEffect(.replace)).accessibilityHidden(true)
            }
        }
    }
}
private struct IslandFooter:View {
    let attributes:ConversationActivityAttributes
    let state:ConversationActivityAttributes.ContentState
    let stale:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            if let preview=state.preview,!preview.isEmpty {
                Text(preview).font(.system(size:12)).foregroundStyle(IslandPalette.moon.opacity(0.82))
                    .lineLimit(2).privacySensitive()
            }
            HStack(spacing:12) {
                if !stale,state.phase == .speaking,let start=state.playbackStart,let end=state.playbackEnd,end>start {
                    ProgressView(timerInterval:start...end,countsDown:false).labelsHidden().tint(IslandPalette.mint)
                } else {
                    Capsule().fill(IslandPalette.glow.opacity(0.32)).frame(height:2)
                }
                Text(ConversationIslandCopy.text("open",language:state.language))
                    .font(.system(size:11,weight:.medium)).foregroundStyle(IslandPalette.mint)
                Image(systemName:"arrow.up.right").font(.system(size:9,weight:.semibold)).foregroundStyle(IslandPalette.mint)
            }
        }
    }
}
private struct ConversationIslandCard:View {
    let attributes:ConversationActivityAttributes
    let state:ConversationActivityAttributes.ContentState
    let stale:Bool
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            IslandAvatar(asset:attributes.avatarAsset,name:attributes.characterName,size:34)
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    IslandName(name:attributes.characterName,state:state,stale:stale)
                    Spacer(minLength:8)
                    IslandSignal(state:state,stale:stale).frame(width:50)
                }
                Text(ConversationIslandCopy.text(stale ? "stale" : state.phase.rawValue,language:state.language))
                    .font(.system(size:12)).foregroundStyle(IslandPalette.moon.opacity(0.72))
                IslandFooter(attributes:attributes,state:state,stale:stale)
            }
        }.foregroundStyle(IslandPalette.moon).padding(16)
    }
}
