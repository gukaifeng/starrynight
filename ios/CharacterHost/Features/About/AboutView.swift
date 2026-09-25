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
                        Text("模型与致谢").font(.headline)
                        Text("RobotExpressive").font(.body.weight(.medium))
                        Text("模型作者：Tomás Laulhé（Quaternius）\n示例整理：Don McCurdy\n许可：CC0 1.0")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Link("查看模型来源 ↗",destination:URL(string:"https://github.com/mrdoob/three.js/tree/r180/examples/models/gltf/RobotExpressive")!)
                            .font(.subheadline).tint(Theme.blue)
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
