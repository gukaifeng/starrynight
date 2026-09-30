import SwiftUI

private struct VoiceArch:Shape {
    var compact=false
    func path(in rect:CGRect)->Path {
        var path=Path();path.move(to:CGPoint(x:0,y:rect.height))
        let shoulder:CGFloat=compact ? 18 : 56
        path.addLine(to:CGPoint(x:0,y:shoulder))
        path.addQuadCurve(to:CGPoint(x:rect.width,y:shoulder),control:CGPoint(x:rect.midX,y:compact ? -6 : -42))
        path.addLine(to:CGPoint(x:rect.width,y:rect.height));path.closeSubpath();return path
    }
}

private struct CaptureWave:View {
    @Bindable var speech:CloudSpeech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || !speech.isRecording)) { timeline in
            Canvas {context,size in
                let time=timeline.date.timeIntervalSinceReferenceDate
                for layer in 0..<3 {
                    var line=Path()
                    for index in 0...96 {
                        let x=Double(index)/96
                        let envelope=pow(sin(x * .pi),1.8)
                        let amplitude=3+Double(speech.inputLevel)*19
                        let y=size.height/2+sin(x * .pi*5-time*4+Double(layer)*0.6)*envelope*amplitude*(1-Double(layer)*0.21)
                        let point=CGPoint(x:x*size.width,y:y)
                        if index==0 {line.move(to:point)} else {line.addLine(to:point)}
                    }
                    context.stroke(line,with:.linearGradient(Gradient(colors:[Theme.accent.opacity(0.15),Theme.ink.opacity(0.85-Double(layer)*0.22),Theme.accent.opacity(0.2)]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:0)),lineWidth:layer==0 ? 1.6 : 1)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct VoiceCaptureOverlay:View {
    @Bindable var session:CompanionSession
    @Binding var editing:Bool
    var compact=false
    var body:some View {
        VStack(spacing:compact ? 5 : 10) {
            if session.voiceInput.phase == .editing {
              if !compact {
                HStack {
                    Text("确认一下，再说给她听").font(.system(size:13,weight:.medium))
                    Spacer()
                    Button {session.cancelVoiceInput();editing=false} label: {Image(systemName:"xmark").font(.system(size:11)).frame(width:36,height:36)}
                        .accessibilityLabel("取消语音消息")
                }
              }
              // Keep this text view's identity when keyboard/rotation changes
              // the available height, preserving focus and marked IME text.
              HStack(alignment:.center,spacing:6) {
                ChatComposerInput(text:Binding(get:{session.voiceInput.text},set:{session.voiceInput.text=$0}),isFocused:$editing,
                    fontSize:15,foreground:UIColor(Theme.ink),accent:UIColor(Theme.accent),maxLines:compact ? 2 : 4,isEnabled:true,
                    onSend:{send()},identifier:"voiceEditText")
                    .frame(minHeight:40).padding(compact ? 8 : 12).background(Theme.ink.opacity(0.055),in:RoundedRectangle(cornerRadius:14))
                if compact {
                    Button {send()} label: {Image(systemName:"arrow.up").font(.system(size:16,weight:.medium)).frame(width:40,height:44)}
                        .disabled(session.voiceInput.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("发送").accessibilityIdentifier("sendVoiceEditButton")
                    Button {session.cancelVoiceInput();editing=false} label: {Image(systemName:"xmark").font(.system(size:12)).frame(width:32,height:44)}
                        .accessibilityLabel("取消语音消息")
                }
              }
              if !compact {
                Button {send()} label: {
                    Text("发送").font(.system(size:14,weight:.medium)).frame(maxWidth:.infinity).padding(.vertical,12)
                        .background(Theme.accent.opacity(0.2),in:Capsule())
                }.disabled(session.voiceInput.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("sendVoiceEditButton")
              }
            } else {
                Label(session.voiceInput.wantsEdit ? "松开后编辑文字" : "上滑到这里，转文字编辑",systemImage:"pencil.line")
                    .font(.system(size:12,weight:.medium)).padding(.horizontal,16).padding(.vertical,9)
                    .background(Theme.ink.opacity(session.voiceInput.wantsEdit ? 0.18 : 0.055),in:Capsule())
                    .accessibilityIdentifier("voiceEditTarget")
                CaptureWave(speech:session.speech).frame(height:compact ? 30 : 48)
                Text(session.speech.recordingTranscript.isEmpty ? (session.speech.isBusy ? "正在准备…" : "正在聆听") : session.speech.recordingTranscript)
                    .font(.system(size:15)).lineSpacing(5).lineLimit(compact ? 2 : 3).frame(maxWidth:.infinity,minHeight:compact ? 26 : 40)
                    .multilineTextAlignment(.center).accessibilityIdentifier("liveVoiceTranscript")
                if session.voiceInput.phase == .finishing {ProgressView().controlSize(.small)}
            }
        }.padding(.horizontal,compact ? 12 : 24).padding(.top,compact ? 24 : 38).padding(.bottom,compact ? 10 : 18)
            .frame(maxWidth:480).foregroundStyle(Theme.ink)
            .background(.ultraThinMaterial,in:VoiceArch(compact:compact))
            .background(Theme.background.opacity(0.76),in:VoiceArch(compact:compact))
            .overlay(VoiceArch(compact:compact).stroke(Theme.gradient.opacity(0.23),lineWidth:0.6))
            .shadow(color:.black.opacity(0.18),radius:22,y:8)
            .conversationHitRegion(.control,id:"voiceCapture")
    }
    private func send() {editing=false;session.sendVoiceText(session.voiceInput.text)}
}
