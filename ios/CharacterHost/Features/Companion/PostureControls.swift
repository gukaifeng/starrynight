import SwiftUI

struct PostureControls: View {
    @Binding var preferences: PosturePreferences
    let profile: PostureProfile
    private var selected: PostureDefinition? { profile.poses.first { $0.id == preferences.id } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("换个舒服的姿势，继续聊").font(.subheadline.weight(.medium))
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                ForEach(profile.poses) { pose in
                    Button { preferences.id = pose.id } label: {
                        Label(pose.label,systemImage:pose.symbol).font(.subheadline.weight(.medium))
                            .frame(maxWidth:.infinity,minHeight:44)
                            .background(preferences.id == pose.id ? Theme.accent.opacity(0.20) : Theme.surface.opacity(0.48),in:RoundedRectangle(cornerRadius:14))
                    }.accessibilityIdentifier("posture-" + pose.id).accessibilityAddTraits(preferences.id == pose.id ? .isSelected : [])
                }
            }
            if let selected {
                ForEach(selected.parameters) { p in
                    VStack(spacing:5) {
                        HStack {
                            Text(p.label).font(.subheadline)
                            Spacer()
                            Text(p.unit == "degrees" ? String(format:"%.0f°",preferences.value(p)) : String(format:"%.0f%%",preferences.value(p)*100))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                        }
                        Slider(value:Binding(get:{preferences.value(p)},set:{preferences.set(p,$0)}),in:p.min...p.max)
                            .accessibilityLabel(p.label).accessibilityIdentifier("postureParameter-" + p.id)
                    }
                }
            }
            Text("也可以直接说“坐下”“上身前倾 6 度”或“把腿收一点”。每种姿势的细节会单独记住。")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
