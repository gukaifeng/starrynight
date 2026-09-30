import SwiftUI
import Observation

struct ThemePalette: Identifiable {
    let id, name, detail: String
    let base, layer, raised, tint, warm, muted, border: UInt32
    var accent: Color { Color(hex:tint) }
    var background: Color { Color(hex:base) }
    static let all: [Self] = [
        .init(id:"silver",name:"月白",detail:"银灰留白，专注彼此",base:0x101114,layer:0x1E2025,raised:0x2B2E35,tint:0xD3DDE9,warm:0xD6C3AA,muted:0xABAEB9,border:0x3F444F),
        .init(id:"aurora",name:"星夜",detail:"黑夜里的彩色微光",base:0x080A10,layer:0x141720,raised:0x202734,tint:0x9DE5DB,warm:0xE9B7C5,muted:0xADB2C5,border:0x353747),
        .init(id:"ocean",name:"深海",detail:"蓝调微光，安静陪伴",base:0x070D17,layer:0x111F2E,raised:0x16293D,tint:0x89CFF1,warm:0xE7C8A4,muted:0xA1B3C4,border:0x2A4055),
        .init(id:"ember",name:"暖夜",detail:"柔和琥珀，像一盏灯",base:0x15100D,layer:0x261E18,raised:0x37291F,tint:0xE6BA83,warm:0xD8A79C,muted:0xBCAF9F,border:0x49392D),
        .init(id:"forest",name:"松林",detail:"墨绿深处，慢慢呼吸",base:0x09130F,layer:0x15271F,raised:0x20382D,tint:0xA0CFB7,warm:0xDDCA9F,muted:0xA4B7AA,border:0x304A3D)
    ]
}
extension ThemeSettings {
    var palette: ThemePalette { ThemePalette.all.first { $0.id == paletteID } ?? ThemePalette.all[0] }
}
extension Color {
    init(hex:UInt32) { self.init(red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255) }
}
@MainActor enum Theme {
    static let brandName = "星夜"
    static let romanName = "StarryNight"
    private static var palette: ThemePalette { ThemeSettings.shared.palette }
    static var background: Color { palette.background }
    static var surface: Color { Color(hex:palette.layer) }
    static var card: Color { Color(hex:palette.raised) }
    static let ink = Color(hex:0xEEF3F6)
    static var secondary: Color { Color(hex:palette.muted) }
    static var accent: Color { palette.accent }
    static var jade: Color { Color(hex:palette.raised) }
    static var peach: Color { Color(hex:palette.warm) }
    static var spectrum: [Color] { palette.id == "aurora" ? [Color(hex:0x9DE5DB),Color(hex:0xB5BFF4),Color(hex:0xE9B7C5),Color(hex:0xEAD4AB)] : [accent,peach] }
    static var gradient: LinearGradient { LinearGradient(colors:spectrum,startPoint:.topLeading,endPoint:.bottomTrailing) }
    static var line: Color { Color(hex:palette.border) }
    static var controlOpacity: Double { ThemeSettings.shared.solid ? 0.94 : 0.5 }
    static var panelOpacity: Double { ThemeSettings.shared.solid ? 0.98 : 0.72 }
}

struct BrandSignature: View {
    var size: CGFloat = 44
    var body: some View {
        HStack(spacing: 12) {
            Image("BrandMark").resizable().scaledToFit()
                .frame(width:size,height:size)
                .clipShape(.rect(cornerRadius:size * 0.25))
                .accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3) {
                Text(Theme.brandName).font(.title3.weight(.semibold)).tracking(3)
                Text(Theme.romanName).font(.system(size:9,weight:.semibold,design:.rounded))
                    .tracking(1.5).foregroundStyle(Theme.secondary)
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel(Theme.brandName)
    }
}
