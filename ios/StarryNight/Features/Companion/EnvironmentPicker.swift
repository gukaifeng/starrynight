import SwiftUI

// Keep the actor visible above the sheet; scene cards use actual engine renders.
struct EnvironmentPicker: View {
    @Binding var draft: CharacterStudio
    var environments: [EnvironmentDescriptor]
    var customize = false
    @State private var category = "all"
    private var descriptor: EnvironmentDescriptor { .find(draft.room) }
    private var tuning: Binding<EnvironmentCustomization> {
        Binding(get:{ draft.resolvedEnvironment },set:{ draft.setEnvironment($0) })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if !customize {
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading,spacing:4) {
                    Text("一起待的地方").font(.title3.weight(.semibold))
                    Text("只属于这个角色的风景，布置也会单独记住。")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength:0)
            }
            Picker("空间类型",selection:$category) {
                Text("全部").tag("all"); Text("室内").tag("indoor"); Text("室外").tag("outdoor")
            }.pickerStyle(.segmented).accessibilityIdentifier("environmentCategory")
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                ForEach(environments.filter { category == "all" || $0.display.category == category }) { scene in
                    Button { draft.selectEnvironment(scene.id) } label: {
                        VStack(alignment:.leading,spacing:0) {
                            Image(scene.display.thumbnail).resizable().scaledToFill().frame(height:88).clipped().contentShape(Rectangle())
                                .overlay(alignment:.topTrailing) {
                                    if draft.room == scene.id {
                                        Image(systemName:"checkmark.circle.fill").foregroundStyle(.white,Theme.accent).padding(7)
                                    }
                                }
                            Text(scene.display.name).font(.subheadline.weight(.medium)).padding(.horizontal,10).padding(.vertical,9)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                            .background(Theme.surface.opacity(draft.room == scene.id ? 0.85 : 0.48))
                            .clipShape(RoundedRectangle(cornerRadius:14))
                            .contentShape(RoundedRectangle(cornerRadius:14))
                            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(draft.room == scene.id ? Theme.accent.opacity(0.7) : .clear,lineWidth:1.5))
                    }.buttonStyle(.plain).accessibilityIdentifier("environment-" + scene.id)
                        .accessibilityLabel(scene.display.name).accessibilityValue(draft.room == scene.id ? "已选择" : "未选择")
                }
            }
            Text(descriptor.display.description).font(.caption).foregroundStyle(Theme.secondary)
            } else {
            HStack {
                Text("空间配色").font(.subheadline.weight(.medium)); Spacer()
                ForEach(descriptor.palettes) { palette in
                    Button { tuning.wrappedValue.palette = palette.id } label: {
                        VStack(spacing:5) {
                            Circle().fill(color(palette.surface)).frame(width:30,height:30)
                                .overlay(Circle().strokeBorder(draft.resolvedEnvironment.palette == palette.id ? Theme.accent : .white,lineWidth:2))
                            Text(palette.name).font(.caption2)
                        }.frame(minWidth:44,minHeight:48)
                    }.buttonStyle(.plain).accessibilityIdentifier("environmentPalette-" + palette.id)
                        .accessibilityLabel(palette.name).accessibilityValue(draft.resolvedEnvironment.palette == palette.id ? "已选择" : "未选择")
                }
            }
            Toggle("摆上装饰",isOn:tuning.decorations).font(.subheadline).accessibilityIdentifier("environmentDecorations")
            VStack(alignment:.leading,spacing:6) {
                HStack { Text("风景的方向").font(.subheadline.weight(.medium)); Spacer(); Text("左右轻转").font(.caption).foregroundStyle(Theme.secondary) }
                Slider(value:tuning.angle,in:-25...25).accessibilityIdentifier("environmentAngle")
            }
            }
        }
    }
    private func color(_ value: String) -> Color {
        let hex = UInt32(value.dropFirst(),radix:16) ?? 0xB7C8BF
        return Color(red:Double((hex >> 16) & 255)/255,green:Double((hex >> 8) & 255)/255,blue:Double(hex & 255)/255)
    }
}
