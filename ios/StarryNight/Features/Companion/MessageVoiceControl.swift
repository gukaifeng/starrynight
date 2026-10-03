import SwiftUI

/// The voice label occupies the reply's raised corner; the bubble owns its single
/// continuous background and outline. There is no second capsule behind this label.
struct MessageVoiceControl: View {
    @Bindable var session: CompanionSession
    let message: CompanionMessage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active:Bool { session.speech.activeMessageID == message.id }
    private var speaking:Bool { active && session.speech.isSpeaking }
    private var measured:TimeInterval? {
        if session.speech.durationSpeeds[message.id] == session.effectiveVoiceSpeed { return session.speech.durations[message.id] }
        // Older packaged introductions may predate persisted duration metadata.
        // Their exact audio length is already known, even before first playback.
        if let id=message.aiScript?.openingID,let opening=CharacterOpenings.find(id),opening.text==message.text {
            return opening.duration
        }
        return message.speechSpeed == session.effectiveVoiceSpeed ? message.speechDuration : nil
    }
    private var durationLabel:String {
        if let measured { return time(measured) }
        // Keep the compact display identical before/after synthesis. Only measured
        // WAV durations are persisted; this fallback is still an in-memory estimate.
        return time(max(1,Double(message.text.count)/(4.5*session.effectiveVoiceSpeed)))
    }
    private func time(_ seconds:TimeInterval) -> String {
        let value = Int(max(0,seconds).rounded(.up))
        return value < 60 ? "\(value)″" : String(format:"%d′%02d″",value/60,value%60)
    }
    private var audioEvidence:String {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return ",audioSegments:\(session.speech.audibleSegments),durationSource:\(measured == nil ? "estimated" : "measured"),voiceMotion:\(speaking && !reduceMotion ? "playing" : "static")"
        }
#endif
        return ""
    }
    var body:some View {
        Button { session.playMessage(message) } label: {
            Group {
                if speaking && !reduceMotion {
                    label.phaseAnimator([false,true]) { content, phase in
                        content.foregroundStyle(Theme.ink.opacity(phase ? 0.98 : 0.58))
                            .shadow(color:Theme.accent.opacity(phase ? 0.28 : 0.04),radius:phase ? 5 : 2)
                    } animation: { _ in .easeInOut(duration:0.9) }
                } else {
                    // Removing the animated subtree stops its timeline completely.
                    // Idle, preparing and completed messages never own a repeat loop.
                    label.foregroundStyle(Theme.ink.opacity(active ? 0.96 : 0.73))
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                }
            }.padding(.top,18)
                .frame(minWidth:44,minHeight:44,alignment:.topLeading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("messageVoice-"+message.id.uuidString)
            .accessibilityLabel(active ? "停止这条语音" : "播放这条语音")
            .accessibilityValue((speaking ? "播放中，" : active ? "准备中，" : "未播放，")+durationLabel+audioEvidence)
            .accessibilityHint("轻点播放或停止这一句台词")
    }
    private var label:some View {
        HStack(spacing:5) {
            Image(systemName:active ? "stop.fill" : "play.fill")
                .font(.system(size:8,weight:.semibold))
            Text(durationLabel).font(.system(size:10,weight:.medium,design:.rounded)).monospacedDigit()
        }
    }
}

/// A single outline rises around the audio label, then eases into the reply's
/// upper edge. The transparent cut-away leaves the character visible beside it.
struct AssistantBubbleShape: Shape {
    func path(in rect:CGRect) -> Path {
        let w = rect.width, h = rect.height, radius:CGFloat = 20
        let shelf = min(76,w-54), shoulder = min(shelf+29,w-radius)
        var p = Path()
        p.move(to:CGPoint(x:radius,y:0))
        p.addLine(to:CGPoint(x:shelf,y:0))
        p.addCurve(to:CGPoint(x:shoulder,y:23),control1:CGPoint(x:shelf+17,y:0),control2:CGPoint(x:shoulder-17,y:23))
        p.addLine(to:CGPoint(x:w-radius,y:23))
        p.addQuadCurve(to:CGPoint(x:w,y:23+radius),control:CGPoint(x:w,y:23))
        p.addLine(to:CGPoint(x:w,y:h-radius))
        p.addQuadCurve(to:CGPoint(x:w-radius,y:h),control:CGPoint(x:w,y:h))
        p.addLine(to:CGPoint(x:radius,y:h))
        p.addQuadCurve(to:CGPoint(x:0,y:h-radius),control:CGPoint(x:0,y:h))
        p.addLine(to:CGPoint(x:0,y:radius))
        p.addQuadCurve(to:CGPoint(x:radius,y:0),control:CGPoint(x:0,y:0))
        p.closeSubpath()
        return p
    }
}
