import SwiftUI

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
                        let amplitude=2+Double(speech.inputLevel)*Double(size.height*0.4-2)
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

/// A quiet floating panel: fixed recording geometry, a live line, and one clear
/// landing area. Only releasing over that area enters the text editor.
struct VoiceCaptureOverlay:View {
    @Bindable var session:CompanionSession
    @Binding var editing:Bool
    var compact=false
    var editTarget:VoiceCaptureTouchTarget?
    var cancelTarget:VoiceCaptureTouchTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var recording:Bool {session.voiceInput.phase != .editing}
    private var shape:RoundedRectangle {RoundedRectangle(cornerRadius:compact ? 18 : 22,style:.continuous)}
    var body:some View {
        VStack(spacing:8) {
            if recording { capture } else { editor }
        }
        .padding(12).frame(maxWidth:360)
        .foregroundStyle(Theme.ink)
        .background {
            if reduceTransparency {shape.fill(Theme.surface)}
            else {shape.fill(.ultraThinMaterial).overlay(shape.fill(Theme.background.opacity(0.76)))}
        }
        .overlay(shape.stroke(LinearGradient(colors:[Theme.accent.opacity(0.25),Theme.ink.opacity(0.04)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.75).allowsHitTesting(false))
        .shadow(color:.black.opacity(0.22),radius:18,y:8)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.15),value:session.voiceInput.editArmed)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.15),value:session.voiceInput.cancelArmed)
        .conversationHitRegion(.control,id:"voiceCapture",enabled:session.voiceInput.active)
        .accessibilityElement(children:.contain)
        .accessibilityIdentifier("voiceCapturePanel")
    }
    private var capture:some View {
        VStack(spacing:8) {
            if !compact {
                HStack(spacing:7) {
                    Circle().fill(Theme.accent.opacity(0.8)).frame(width:4,height:4)
                    Text(session.voiceInput.needsReview ? "松开后确认文字" : (session.voiceInput.resultReady ? "语音已收好" : "正在聆听"))
                        .font(.system(size:11,weight:.medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(session.voiceInput.phase == .holding ? "松开发送" : "正在整理")
                        .font(.system(size:11)).foregroundStyle(Theme.ink.opacity(0.4))
                }
            }
            CaptureWave(speech:session.speech).frame(height:compact ? 16 : 20)
            Text(transcript)
                .font(.system(size:14)).lineSpacing(3).lineLimit(compact ? 1 : 2)
                .frame(maxWidth:.infinity).frame(height:compact ? 20 : 36)
                .multilineTextAlignment(.center).foregroundStyle(Theme.ink.opacity(session.voiceInput.text.isEmpty ? 0.46 : 0.9))
                .accessibilityIdentifier("liveVoiceTranscript")
            if session.voiceInput.phase != .finishing {
                HStack(spacing:10) {
                    landingZone(cancel:true)
                    landingZone(cancel:false)
                }
            } else {
                HStack(spacing:8) {
                    ProgressView().controlSize(.mini)
                    Text("正在确认最后一句").font(.system(size:12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("取消") {session.cancelVoiceInput()}
                        .font(.system(size:12)).frame(minWidth:44,minHeight:40)
                        .accessibilityLabel("取消语音消息")
                }.frame(height:compact ? 40 : 46)
            }
        }.allowsHitTesting(session.voiceInput.phase != .holding)
    }
    private func landingZone(cancel:Bool)->some View {
        let armed=cancel ? session.voiceInput.cancelArmed : session.voiceInput.editArmed
        let tint=cancel ? Theme.peach : Theme.accent
        return HStack(spacing:6) {
            Image(systemName:cancel ? "xmark" : "pencil.line").font(.system(size:11,weight:.medium))
            Text(armed ? (cancel ? "松开取消" : "松开编辑") : (cancel ? "上滑取消" : "上滑编辑"))
                .font(.system(size:12,weight:.medium))
        }.frame(maxWidth:.infinity).frame(height:40)
            .foregroundStyle(armed ? tint : Theme.secondary)
            .background(tint.opacity(armed ? 0.2 : 0.055),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(tint.opacity(armed ? 0.48 : 0.08),lineWidth:0.75))
            .background {if let target=cancel ? cancelTarget : editTarget {VoiceEditTargetAnchor(target:target)}}
            .accessibilityElement(children:.ignore).accessibilityLabel(cancel ? "上滑取消区域" : "上滑编辑区域")
            .accessibilityValue(armed ? "已选中，松开确认" : "未选中")
            .accessibilityIdentifier(cancel ? "voiceCancelTarget" : "voiceEditTarget")
    }
    private var transcript:String {
        if !session.voiceInput.text.isEmpty {return session.voiceInput.text}
        if session.voiceInput.needsReview {return session.speech.error ?? "这次没有听清，松开后可以输入文字"}
        return session.speech.isBusy ? "正在打开麦克风…" : "轻声说，我在听"
    }
    private var editor:some View {
        VStack(spacing:compact ? 5 : 10) {
            if !compact {
                HStack {
                    Text("确认一下，再发给她").font(.system(size:13,weight:.medium))
                    Spacer()
                    Button {session.cancelVoiceInput();editing=false} label: {
                        Image(systemName:"xmark").font(.system(size:11)).frame(width:36,height:36)
                    }.accessibilityLabel("取消语音消息")
                }
            }
            // The editor opens on release with the current partial text. A late
            // ASR final may improve it only until the user starts correcting it.
            HStack(alignment:.center,spacing:6) {
                ChatComposerInput(text:Binding(get:{session.voiceInput.text},set:{session.voiceInput.edit($0)}),isFocused:$editing,
                    fontSize:15,foreground:UIColor(Theme.ink),accent:UIColor(Theme.accent),maxLines:compact ? 2 : 4,isEnabled:true,
                    onSend:{send()},identifier:"voiceEditText")
                    .frame(minHeight:40).padding(compact ? 8 : 12)
                    .background(Theme.ink.opacity(0.055),in:RoundedRectangle(cornerRadius:14))
                if compact {
                    Button {send()} label: {Image(systemName:"arrow.up").font(.system(size:16,weight:.medium)).frame(width:40,height:44)}
                        .disabled(session.voiceInput.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("发送").accessibilityIdentifier("sendVoiceEditButton")
                    Button {session.cancelVoiceInput();editing=false} label: {Image(systemName:"xmark").font(.system(size:12)).frame(width:32,height:44)}
                        .accessibilityLabel("取消语音消息")
                }
            }
            if !compact {
                HStack {
                    Text(session.voiceInput.needsReview ? (session.speech.error ?? "已保留识别文字，请确认后发送") :
                        (session.voiceInput.resultReady ? "可以修改识别出的文字" : "还在整理最后一句，可以先修改"))
                        .font(.system(size:11)).lineLimit(2).foregroundStyle(Theme.secondary)
                    Spacer(minLength:8)
                    Button {send()} label: {
                        Text("发送").font(.system(size:14,weight:.medium)).padding(.horizontal,20).frame(height:40)
                            .background(Theme.accent.opacity(0.16),in:Capsule())
                    }.disabled(session.voiceInput.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("sendVoiceEditButton")
                }
            }
        }
    }
    private func send() {editing=false;session.sendVoiceText(session.voiceInput.text)}
}
