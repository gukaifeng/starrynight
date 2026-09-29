import SwiftUI

struct SoundscapePanel: View {
    @Bindable var soundscape: CompanionSoundscape
    @Environment(\.softPanelDismiss) private var dismiss
    var body: some View {
        VStack(spacing:0) {
            PanelPageHeader("此刻的音乐",backID:"closeMusicButton")
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("让这一刻，慢一点。").font(.title2.weight(.medium))
                        Text("属于这位角色的旋律，陪我们的对话慢慢流动。").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    ForEach(soundscape.availableTracks) { track in
                        Button { soundscape.select(track.id) } label: {
                            HStack(spacing:16) {
                                Image(systemName:track.symbol).font(.title2).frame(width:48,height:48)
                                    .background(Theme.jade.opacity(0.35),in:RoundedRectangle(cornerRadius:16))
                                VStack(alignment:.leading,spacing:5) {
                                    Text(track.title).font(.headline)
                                    Text(track.detail).font(.caption).foregroundStyle(Theme.secondary)
                                    if let duration = track.durationLabel {
                                        Text(duration).font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary.opacity(0.8))
                                    }
                                }
                                Spacer(minLength:0)
                                if soundscape.trackID == track.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.accent) }
                            }.padding(16).background(Theme.surface.opacity(0.7),in:RoundedRectangle(cornerRadius:24))
                        }.buttonStyle(.plain).accessibilityIdentifier("musicTrack-" + track.id)
                    }
                    VStack(spacing:14) {
                        HStack {
                            Text("音乐音量").font(.subheadline)
                            Spacer()
                            Text("\(Int((soundscape.volume*100).rounded()))%").monospacedDigit().foregroundStyle(Theme.secondary).accessibilityIdentifier("musicVolumeValue")
                        }
                        Slider(value:Binding(get:{ soundscape.volume },set:{ value in soundscape.setVolume(value) }),in:0...1,step:0.05)
                            .accessibilityLabel("背景音乐音量").accessibilityIdentifier("musicVolumeSlider")
                        HStack {
                            Button("轻一点 · 15%") { soundscape.setVolume(0.15) }.accessibilityIdentifier("musicQuietButton")
                            Spacer()
                            Button("适中 · 35%") { soundscape.setVolume(0.35) }.accessibilityIdentifier("musicMediumButton")
                        }.font(.caption)
                    }.padding(.horizontal,4)
                    Button { soundscape.toggle() } label: {
                        Label(soundscape.enabled && !soundscape.interrupted ? "暂停音乐" : "播放音乐",systemImage:soundscape.enabled && !soundscape.interrupted ? "pause.fill" : "play.fill")
                            .font(.headline).frame(maxWidth:.infinity,minHeight:52).background(Theme.accent,in:Capsule()).foregroundStyle(Theme.background)
                    }.accessibilityIdentifier("musicToggleButton").accessibilityValue(soundscape.accessibilityEvidence)
                    Text(soundscape.status).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("musicStatus")
                    Text("角色说话时，音乐会轻下来；录音时暂停。离开聊天空间或锁屏后也会暂停。")
                        .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(.horizontal,22).padding(.bottom,24)
            }.scrollIndicators(.hidden).background(Color.clear)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
    }
}
