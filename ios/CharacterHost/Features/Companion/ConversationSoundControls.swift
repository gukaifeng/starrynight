import SwiftUI

struct ConversationSoundButton: View {
    let session: CompanionSession
    var onSettings: () -> Void
    var body: some View {
        Button(action:onSettings) {
            Image(systemName:session.soundscape.masterMuted ? "speaker.slash" : "speaker.wave.1")
                .font(.system(size:14,weight:.regular)).foregroundStyle(Theme.ink.opacity(0.56))
                .frame(width:44,height:36).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("声音设置")
            .accessibilityValue(session.soundscape.accessibilityEvidence)
            .accessibilityIdentifier("conversationSoundButton")
    }
}

struct ConversationSoundPanel: View {
    let session: CompanionSession
    private var audio: CompanionSoundscape { session.soundscape }
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("声音 · " + session.record.profile.name,backID:"closeConversationSound")
            ScrollView {
                VStack(spacing:4) {
                    VStack(spacing:0) {
                        channel("心声",symbol:"quote.bubble",volume:Binding(get:{audio.speechVolume},set:{session.setSpeechVolume($0)}),id:"speech")
                        separator
                        channel("背景音乐",symbol:"music.note",volume:Binding(get:{audio.volume},set:{audio.setVolume($0)}),id:"music")
                    }
                    HStack(spacing:5) {
                        Image(systemName:"opticaldisc").font(.system(size:10))
                        Text(audio.track?.title ?? "专属配乐").lineLimit(1)
                        Spacer(minLength:8)
                        Text("滑至最左即静音")
                    }.font(.system(size:10)).foregroundStyle(Theme.secondary.opacity(0.75))
                }.padding(.horizontal,24).padding(.bottom,10)
            }.scrollIndicators(.hidden)
        }.softPanelPageSurface().foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
    }
    private var separator: some View { Rectangle().fill(Theme.line.opacity(0.16)).frame(height:0.5) }
    private func channel(_ title:String,symbol:String,volume:Binding<Double>,id:String)->some View {
        HStack(spacing:8) {
            Image(systemName:volume.wrappedValue == 0 ? "speaker.slash" : symbol)
                .font(.system(size:12,weight:.light)).frame(width:17).foregroundStyle(Theme.secondary)
            Text(title).font(.system(size:12,weight:.medium)).frame(width:54,alignment:.leading)
            Slider(value:volume,in:0...1)
                .accessibilityLabel(title+"音量").accessibilityIdentifier(id+"SoundVolume")
            Text(volume.wrappedValue == 0 ? "静音" : "\(Int((volume.wrappedValue*100).rounded()))%")
                .font(.system(size:10).monospacedDigit()).foregroundStyle(Theme.secondary)
                .frame(width:32,alignment:.trailing)
        }.frame(minHeight:42)
    }
}
