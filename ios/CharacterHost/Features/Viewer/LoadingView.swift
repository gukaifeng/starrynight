import SwiftUI

/// A small card laid over the selected portrait; the home and role stay visible.
struct LoadingView: View {
    var failed: Bool
    var errorMessage: String
    var onCancel: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(alignment:.center,spacing:14) {
            Group {
                if failed { Image(systemName:"exclamationmark.triangle").font(.title2) }
                else { ProgressView().tint(Theme.accent) }
            }.frame(width:26).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:5) {
                Text(failed ? "暂时无法打开角色" : "正在准备角色")
                    .font(.subheadline.weight(.semibold))
                Text(failed ? errorMessage : "马上就能见面了")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            Button(action:onCancel) {
                Image(systemName:"xmark").font(.system(size:14,weight:.medium)).frame(width:44,height:44)
                    .background(Theme.card.opacity(0.7),in:Circle())
            }.buttonStyle(.plain).accessibilityLabel(failed ? "返回角色选择" : "取消打开角色")
                .accessibilityIdentifier("cancelLoadingButton")
        }.padding(16).foregroundStyle(Theme.ink)
            .background(Theme.background.opacity(reduceTransparency ? 1 : 0.94),in:RoundedRectangle(cornerRadius:24))
            .overlay(RoundedRectangle(cornerRadius:24).stroke(Theme.line.opacity(0.8),lineWidth:1))
            .shadow(color:Theme.ink.opacity(0.08),radius:16,y:4)
            .accessibilityElement(children:.contain)
    }
}
