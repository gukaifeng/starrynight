import SwiftUI

/// Fictional inner voice and grounded narration are visually distinct and never
/// part of the spoken text. No provider markup or resource IDs are displayed.
struct AIReplyContent: View {
    let message: CompanionMessage
    let fontSize: CGFloat
    private var asideFont:Font {
        let size=max(12,fontSize-1)
        let base=UIFont(name:"Kaiti SC",size:size) ?? UIFont.systemFont(ofSize:size)
        // CJK fallback faces often have no italic cut; explicitly slant the
        // glyph matrix, preserving native wrapping and selectable text.
        let descriptor=base.fontDescriptor.withMatrix(CGAffineTransform(a:1,b:0,c:0.14,d:1,tx:0,ty:0))
        return Font(UIFont(descriptor:descriptor,size:size))
    }
    private func aside(_ text:String)->String {"（"+text.trimmingCharacters(in:CharacterSet(charactersIn:"（）() \n"))+"）"}
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            if let script = message.aiScript {
                ForEach(script.beats) { beat in
                    ForEach(Array(beat.visibleNarrations.enumerated()),id:\.offset) { _, narration in
                        Text(aside(narration.text)).font(asideFont)
                            .foregroundStyle(Theme.secondary.opacity(0.92)).lineSpacing(3)
                            .accessibilityLabel("旁白："+narration.text)
                            .accessibilityIdentifier("aiNarration")
                    }
                    if let text = beat.visibleThought {
                        HStack(alignment:.firstTextBaseline,spacing:5) {
                            Image(systemName:"sparkle").font(.system(size:8,weight:.light))
                            Text(aside(text)).font(asideFont).lineSpacing(3)
                        }.foregroundStyle(Theme.peach.opacity(0.8))
                            .accessibilityLabel("角色心声："+text).accessibilityIdentifier("aiThought")
                    }
                    if let dialogue = beat.dialogue {
                        Text(dialogue.text).font(.system(size:fontSize)).lineSpacing(5)
                            .fixedSize(horizontal:false,vertical:true)
                            .accessibilityIdentifier("assistantMessage")
                            .accessibilityValue(message.proactiveScene.map { "主动问候："+$0 } ?? "AI 回复")
                    }
                }
            } else {
                Text(message.text).font(.system(size:fontSize)).lineSpacing(5).accessibilityIdentifier("assistantMessage")
            }
        }.fixedSize(horizontal:false,vertical:true)
    }
}
