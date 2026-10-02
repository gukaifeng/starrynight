import SwiftUI

/// Fictional inner voice and grounded narration are visually distinct and never
/// part of the spoken text. No provider markup or resource IDs are displayed.
struct AIReplyContent: View {
    let message: CompanionMessage
    let fontSize: CGFloat
    var reveal: ReplyReveal = ReplyReveal()
    var translation: [String:String] = [:]
    private func translated(_ text:String,_ id:String) -> String { translation[id] ?? text }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var asideFont:Font {
        let size=max(12,fontSize-1)
        let base=UIFont(name:"Kaiti SC",size:size) ?? UIFont.systemFont(ofSize:size)
        // CJK fallback faces often have no italic cut; explicitly slant the
        // glyph matrix, preserving native wrapping and selectable text.
        let descriptor=base.fontDescriptor.withMatrix(CGAffineTransform(a:1,b:0,c:0.14,d:1,tx:0,ty:0))
        return Font(UIFont(descriptor:descriptor,size:size))
    }
    private func aside(_ text:String)->String {"（"+ReplyDisplayText.flatten(text)+"）"}
    private func dialogue(_ text:String)->AttributedString {
        var output=AttributedString()
        for piece in ReplyDisplayText.pieces(text) {
            var run=AttributedString(piece.aside ? aside(piece.text) : piece.text)
            run.font=piece.aside ? asideFont : .system(size:fontSize)
            run.foregroundColor=piece.aside ? (AIBeat.visibleThought(piece.text) != nil ? Theme.peach.opacity(0.8) : Theme.secondary.opacity(0.92)) : Theme.ink
            output.append(run)
        }
        return output
    }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            if let script = message.aiScript {
                ForEach(script.beats) { beat in
                  if let parts=beat.parts {
                    ForEach(Array(parts.prefix(reveal.count(message.id,beat:beat.beatId) ?? parts.count).enumerated()),id:\.offset) { index,part in
                        if part.isVisible {
                            let text = translated(part.text,beat.beatId + ".part.\(index)")
                            Text(part.kind == "dialogue" ? dialogue(text) : AttributedString(aside(text)))
                                .font(part.kind == "dialogue" ? .system(size:fontSize) : asideFont)
                                .foregroundStyle(part.kind == "dialogue" ? Theme.ink : part.kind == "thought" ? Theme.peach.opacity(0.8) : Theme.secondary.opacity(0.92))
                                .lineSpacing(part.kind == "dialogue" ? 5 : 3)
                                .fixedSize(horizontal:false,vertical:true)
                                .accessibilityIdentifier(part.kind == "dialogue" ? "assistantMessage" : part.kind == "thought" ? "aiThought" : "aiNarration")
                                .transition(.opacity)
                        }
                    }
                  } else {
                    ForEach(Array(beat.narrations.enumerated().filter { $0.element.isVisible }),id:\.offset) { index, narration in
                        Text(aside(translated(narration.text,beat.beatId + ".narration.\(index)"))).font(asideFont)
                            .foregroundStyle(Theme.secondary.opacity(0.92)).lineSpacing(3)
                            .accessibilityLabel("旁白："+narration.text)
                            .accessibilityIdentifier("aiNarration")
                    }
                    if let text = beat.visibleThought {
                        HStack(alignment:.firstTextBaseline,spacing:5) {
                            Image(systemName:"sparkle").font(.system(size:8,weight:.light))
                            Text(aside(translated(text,beat.beatId + ".thought"))).font(asideFont).lineSpacing(3)
                        }.foregroundStyle(Theme.peach.opacity(0.8))
                            .accessibilityLabel("角色心声："+text).accessibilityIdentifier("aiThought")
                    }
                    if let dialogue = beat.dialogue {
                        Text(self.dialogue(translated(dialogue.text,beat.beatId + ".dialogue"))).font(.system(size:fontSize)).lineSpacing(5)
                            .fixedSize(horizontal:false,vertical:true)
                            .accessibilityIdentifier("assistantMessage")
                            .accessibilityValue(message.proactiveScene.map { "主动问候："+$0 } ?? "AI 回复")
                    }
                  }
                }
            } else {
                Text(dialogue(translated(message.text,"text"))).font(.system(size:fontSize)).lineSpacing(5).accessibilityIdentifier("assistantMessage")
            }
        }.fixedSize(horizontal:false,vertical:true)
            .animation(.easeInOut(duration:reduceMotion ? 0.01 : 0.22),value:reveal.revision)
    }
}
