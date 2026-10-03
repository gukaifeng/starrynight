import SwiftUI

struct ConversationSoundControls: View {
    let session: CompanionSession
    private var audio: CompanionSoundscape { session.soundscape }
    var body: some View {
        VStack(spacing:2) {
            channel("角色语音",symbol:"speaker.wave.1",volume:Binding(get:{audio.speechVolume},set:{session.setSpeechVolume($0)}),id:"speech")
            separator
            channel("背景音乐",symbol:"music.note",volume:Binding(get:{audio.volume},set:{audio.setVolume($0)}),id:"music")
            HStack(spacing:4) {
                Image(systemName:"opticaldisc").font(.system(size:9))
                Text(audio.track?.title ?? "专属配乐").lineLimit(1)
                Spacer(minLength:4)
                Text("最左为静音")
            }.font(.system(size:9)).foregroundStyle(Theme.secondary.opacity(0.75))
        }.foregroundStyle(Theme.ink).tint(Theme.accent)
    }

    private var separator: some View { Rectangle().fill(Theme.line.opacity(0.16)).frame(height:0.5) }
    private func channel(_ title:String,symbol:String,volume:Binding<Double>,id:String)->some View {
        HStack(spacing:8) {
            Image(systemName:volume.wrappedValue == 0 ? "speaker.slash" : symbol)
                .font(.system(size:12,weight:.light)).frame(width:17).foregroundStyle(Theme.secondary)
            Text(LocalizedStringKey(title)).font(.system(size:12,weight:.medium)).frame(width:76,alignment:.leading).lineLimit(2).minimumScaleFactor(0.8)
            Slider(value:volume,in:0...1)
                .accessibilityLabel(L10n.text(title)+" · "+L10n.text("音量")).accessibilityIdentifier(id+"SoundVolume")
            Text(volume.wrappedValue == 0 ? "静音" : "\(Int((volume.wrappedValue*100).rounded()))%")
                .font(.system(size:10).monospacedDigit()).foregroundStyle(Theme.secondary)
                .frame(width:32,alignment:.trailing)
        }.frame(minHeight:40)
    }
}
