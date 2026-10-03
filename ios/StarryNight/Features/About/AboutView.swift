import SwiftUI

struct AboutView: View {
    var embedded = false
    @Environment(\.softPanelDismiss) private var dismiss
    private var modelCredits: String {
        guard let url = Bundle.main.url(forResource:"MikuCredits",withExtension:"txt"),
              let text = try? String(contentsOf:url,encoding:.utf8) else { return "模型说明暂不可用" }
        return text
    }
    private var humanCredits: String {
        guard let url = Bundle.main.url(forResource:"RealCharacterCredits",withExtension:"txt"),
              let text = try? String(contentsOf:url,encoding:.utf8) else { return "模型说明暂不可用" }
        return text
    }
    var body: some View {
        Group {
            if embedded { content }
            else {
                NavigationStack {
                    content.navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeAboutButton") } }
                }
            }
        }.preferredColorScheme(.dark).softSheetSurface()
    }
    private var content: some View {
            ScrollView {
                VStack(alignment:.leading,spacing:28) {
                    BrandSignature(size:64)
                    VStack(alignment:.leading,spacing:8) {
                        Text("让陪伴，更近一点。").font(.title2.weight(.medium))
                        Text("一个能聊天、会回应的小伙伴。")
                            .font(.body).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment:.leading,spacing:16) {
                        Text("走近角色").font(.headline)
                        Label("对话近景或全身互动",systemImage:"hand.draw")
                        Label("定制里解锁位置后，轻拖转向、双指缩放",systemImage:"arrow.up.left.and.arrow.down.right")
                        Label("取景面板恢复推荐构图",systemImage:"arrow.counterclockwise")
                        Label("点动作按钮，让它挥手、跳跃或跳舞",systemImage:"hand.wave")
                        Label("轻触角色头部，它会摇摇头",systemImage:"hand.tap")
                        Label("轻点聊天工具栏的挥手图标，选择动作",systemImage:"hand.draw")
                    }.font(.subheadline)
                    Divider()
                    VStack(alignment:.leading,spacing:9) {
                        Text("模型与画质").font(.headline)
                        Text("小夏 · 写实女性").font(.body.weight(.medium))
                        Text("可定制面容、身形、肤色、发型与衣服配色；皮肤纹理、发丝贴图与针织法线。三种空间背景，光源方向、高度、亮度及影子深浅可调。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        NavigationLink("写实角色来源与署名") {
                            ScrollView { Text(humanCredits).font(.caption).textSelection(.enabled).padding() }.scrollIndicators(.hidden)
                                .softNavigationBackground().navigationTitle("写实角色署名")
                        }
                        Text("Luma · Studio Robot").font(.body.weight(.medium))
                        Text("项目原创模型与动作\n陶瓷外壳 · 金属关节 · 实时柔和阴影\n原生分辨率 · 4 倍抗锯齿")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Text("初音未来 · 同人模型").font(.body.weight(.medium))
                        Text("Tda 式 Append · 精细面部 · 完整服装贴图\n鞠躬、转身、致意、应援等动作")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Text("模型原作者 Tda，改作者 monjo3456；星夜完成 Unity 适配与交互动作。Hatsune Miku © Crypton Future Media, Inc.。这是非官方的个人非商业测试作品，遵循原模型使用规约与 Piapro Character License。")
                            .font(.caption).foregroundStyle(Theme.secondary)
                        Link("角色来源与使用说明",destination:URL(string:"https://piapro.net/intl/en_for_creators.html")!)
                        NavigationLink("完整模型署名与使用说明") {
                            ScrollView { Text(modelCredits).font(.caption).textSelection(.enabled).padding() }.scrollIndicators(.hidden)
                                .softNavigationBackground().navigationTitle("模型使用说明")
                        }
                        NavigationLink("角色与场景的来源和许可") {
                            ScrollView {
                                Text(Bundle.main.url(forResource:"CharacterPackageCredits",withExtension:"txt").flatMap { try? String(contentsOf:$0,encoding:.utf8) } ?? "暂无更多角色许可")
                                    .font(.caption).textSelection(.enabled).padding()
                            }.scrollIndicators(.hidden).softNavigationBackground().navigationTitle("角色与场景许可")
                        }
                        Text("默认以 120 FPS 为渲染目标，可在内部性能诊断页切换为 60 FPS。性能诊断页可查看实测渲染循环帧率；屏幕刷新率、系统设置与设备温度会影响实际表现。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment:.leading,spacing:9) {
                        Text("关于星夜").font(.headline)
                        Text("小猫与豆日向拥有独立的人设、记忆和原创音色。真实对话由百炼角色模型生成，表情从角色已有资源中选择；台词、心声与旁白分别呈现，只有台词和自然声音事件会被朗读。内容由 AI 生成。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Text("AI 连接与资料").font(.headline)
                        Text("对话和已确认记忆会发送到星夜后端及阿里云百炼，用于生成回应。录音只在点击麦克风后实时发送识别，结果可编辑，确认发送后才进入聊天。角色语音由 AI 合成。开发版后端运行在 Mac，同一网络可用；后续部署独立服务后即可离开 Mac 使用。密钥仅存后端。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Text("本机保留最近 1,000 条消息和可清理的语音缓存；后端按用户与角色独立保存上下文。旧测试记录已备份，不参与真实对话。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                        Link("阿里云百炼",destination:URL(string:"https://help.aliyun.com/zh/model-studio/")!)
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Text("此刻的音乐").font(.headline)
                        Text("内置「岛上的午后」与「月光潮汐」，离线播放、独立音量。角色说话时自动降低音乐，录音和离开聊天空间时暂停。两段器乐由本项目编排与程序合成，不使用第三方录音。")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 让陪伴，更近一点")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }.padding(28).frame(maxWidth:600).frame(maxWidth:.infinity)
            }.scrollIndicators(.hidden).background(Color.clear)
                .softNavigationBackground()
    }
}
