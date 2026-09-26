import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:28) {
                    Image(systemName:"cube.transparent.fill").font(.largeTitle).foregroundStyle(Theme.blue)
                    VStack(alignment:.leading,spacing:8) {
                        Text("模型空间").font(.largeTitle.bold())
                        Text("留一点时间，换一个角度。")
                            .font(.body).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment:.leading,spacing:16) {
                        Text("自由查看").font(.headline)
                        Label("单指拖动，环绕观察模型",systemImage:"hand.draw")
                        Label("双指张合，拉近或拉远",systemImage:"arrow.up.left.and.arrow.down.right")
                        Label("轻点复位，回到初始视角",systemImage:"arrow.counterclockwise")
                        Label("点动作按钮，让它挥手、跳跃或跳舞",systemImage:"hand.wave")
                        Label("轻触机器人头部，它会摇摇头",systemImage:"hand.tap")
                    }.font(.subheadline)
                    Divider()
                    VStack(alignment:.leading,spacing:9) {
                        Text("模型与画质").font(.headline)
                        Text("Luma · Studio Robot").font(.body.weight(.medium))
                        Text("项目原创模型与动作\n陶瓷外壳 · 金属关节 · 实时柔和阴影\n原生分辨率 · 4 倍抗锯齿")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Text("默认以 120 FPS 为渲染目标，可在查看器切换为 60 FPS。上方数字为实测渲染循环帧率；屏幕刷新率、系统设置与设备温度会影响实际表现。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    Text("版本 1.0 · 所有模型资源均已内置")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }.padding(28).frame(maxWidth:600).frame(maxWidth:.infinity)
            }.background(Theme.background)
                .navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.confirmationAction) {
                        Button("完成") { dismiss() }.accessibilityIdentifier("closeAboutButton")
                    }
                }
        }.preferredColorScheme(.light)
    }
}
