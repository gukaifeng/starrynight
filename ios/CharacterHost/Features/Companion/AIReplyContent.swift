import SwiftUI

/// Fictional inner voice and grounded narration are visually distinct and never
/// part of the spoken text. No provider markup or resource IDs are displayed.
struct AIReplyContent: View {
    let message: CompanionMessage
    let fontSize: CGFloat
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            if let script = message.aiScript {
                ForEach(script.beats) { beat in
                    if let dialogue = beat.dialogue {
                        Text(dialogue.text).font(.system(size:fontSize)).lineSpacing(5)
                            .fixedSize(horizontal:false,vertical:true)
                            .accessibilityIdentifier("assistantMessage")
                            .accessibilityValue(message.proactiveScene.map { "主动问候："+$0 } ?? "AI 回复")
                    }
                    ForEach(Array(beat.narrations.enumerated()),id:\.offset) { _, narration in
                        Text(narration.text).font(.system(size:max(11,fontSize-2))).italic()
                            .foregroundStyle(Theme.secondary.opacity(0.85)).lineSpacing(3)
                            .accessibilityIdentifier("aiNarration")
                    }
                    if let text = beat.visibleThought {
                        HStack(alignment:.firstTextBaseline,spacing:5) {
                            Image(systemName:"sparkle").font(.system(size:8,weight:.light))
                            Text(text).font(.system(size:max(11,fontSize-2))).lineSpacing(3)
                        }.foregroundStyle(Theme.peach.opacity(0.8))
                            .accessibilityLabel("角色心声："+text).accessibilityIdentifier("aiThought")
                    }
                }
            } else {
                Text(message.text).font(.system(size:fontSize)).lineSpacing(5).accessibilityIdentifier("assistantMessage")
            }
        }.fixedSize(horizontal:false,vertical:true)
    }
}
