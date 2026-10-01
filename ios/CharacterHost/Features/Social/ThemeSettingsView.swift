import SwiftUI

struct ThemeSettingsView: View {
    @Bindable private var settings = ThemeSettings.shared
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:8) {
                    Text("给陪伴，一种喜欢的颜色").font(.title3.weight(.medium))
                    Text("只改变界面；角色的外观和空间会保留。")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                ForEach(ThemePalette.all) { palette in
                    Button { withAnimation(.easeInOut(duration:0.3)) { settings.paletteID = palette.id } } label: {
                        HStack(spacing:14) {
                            ZStack {
                                RoundedRectangle(cornerRadius:16).fill(palette.background)
                                Circle().stroke(palette.accent,lineWidth:3).frame(width:25,height:25).offset(x:-5)
                                Circle().fill(palette.accent.opacity(0.7)).frame(width:16,height:16).offset(x:10,y:4)
                            }.frame(width:56,height:56)
                            VStack(alignment:.leading,spacing:5) {
                                Text(LocalizedStringKey(palette.name)).font(.subheadline.weight(.semibold))
                                Text(LocalizedStringKey(palette.detail)).font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength:0)
                            Image(systemName:settings.paletteID == palette.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(palette.accent)
                        }.padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:20))
                    }.buttonStyle(.plain).accessibilityIdentifier("theme-"+palette.id)
                        .accessibilityValue(settings.paletteID == palette.id ? "已选择" : "未选择")
                }
                VStack(alignment:.leading,spacing:12) {
                    Text("界面质感").font(.headline)
                    Picker("界面质感",selection:$settings.style) {
                        Text("轻透").tag("glass"); Text("沉静").tag("solid")
                    }.pickerStyle(.segmented).accessibilityIdentifier("themeStyle")
                    Text(settings.solid ? "更沉稳的面板和按钮，文字更醒目。" : "柔和的半透明层次，和角色自然相融。")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                HStack {
                    Image(systemName:"speaker.wave.2").frame(width:34,height:34)
                        .background(Theme.surface.opacity(Theme.controlOpacity),in:Circle())
                    Text("此刻，我在听。 ").font(.subheadline)
                    Spacer()
                    Image(systemName:"arrow.up.circle.fill").foregroundStyle(Theme.accent)
                }.padding(16).background(Theme.card.opacity(Theme.panelOpacity),in:RoundedRectangle(cornerRadius:22))
            }.padding(24)
        }.scrollIndicators(.hidden).background(Theme.background)
            .foregroundStyle(Theme.ink).tint(Theme.accent).navigationTitle("主题与样式").navigationBarTitleDisplayMode(.inline)
    }
}
