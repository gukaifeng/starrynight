# 持续姿势与对话配置验证 · 0.11.0 / build 20

2026-09-28。实现范围包括小夏的站立、地面坐姿、蹲下、侧躺，以及各自保存的上身前倾、身体朝向、双腿间距、手臂舒展。独立 GLB 小乐提供站立/坐姿及前倾样例；旧 Luma、初音缺少姿势资源时明确降级，不强行改骨架。

制作标准与机器协议见 [姿势标准](../../character-standard/05-posture-standard.md)、[其他 AI 任务书](../../character-standard/03-ai-handoff.md)。XCP / Character API 升级为 1.1，schemaVersion / apiMajor 保持 1，新增 required 能力 core.posture@1。XEP 协议仍为 1.0，部分场景资源升级 1.0.1 以覆盖低机位地面。

## 实际验证

| 检查 | 结果与证据 |
|---|---|
| 角色 SDK 正反例 | 34 项通过，sdk-tests.txt；包含 13 项姿势契约检查 |
| Swift 解析与存档核心 | 18 项通过，swift-core-tests.txt |
| 四角色源包预检 | 通过，preflight.json |
| Unity 姿势运行时 | 52 项通过，engine-review.json |
| 既有角色平台回归 | 78 项通过，platform-regression.json |
| 两两姿势转换地面检查 | 294 个实际变形网格采样通过，transition-contact-audit.json |
| 场景 SDK / 六场景预检 | 15 项及六场景通过，environment-tests.txt / environment-preflight.json |
| iPhone 17 完整姿势流程 | 通过，Posture-Phone-Final.xcresult，80.507 秒 |
| iPad Pro 11 英寸 M4 完整姿势流程 | 通过，Posture-iPad-Landscape.xcresult，87.309 秒；含镜头收稳与脸部避开聊天栏断言 |
| 独立 GLB / 旧包降级 / 角色平台 UI 回归 | 2 项通过，Posture-Compatibility-Final.xcresult，68.976 秒 |
| SDK 独立解压验收 | 见 standalone-sdk.json：不依赖 Unity 缓存，独立运行示例预检与工具测试 |

原始 xcresult / 构建日志保留在仓库 .local/checks / .local/logs。横屏构图修正前 iPad 完整流程也通过（95.980 秒），其截图发现的遮脸问题另行修正并复测；iPhone 完整流程录制于该最后修正之前，竖屏不进入新横屏分支，已重新安装最终构建并启动。最终轮与中途失败结果分开保留；以 results.json 中列明的版本和轮次为准。

完整流程实际操作：聊天坐下 → 触头摇头后仍坐着 → 前倾 6 度/收腿 → 否定指令不改变 → 姿势面板精调 → 连续打断切换 → 取消还原 → 蹲下/侧躺 → 换花园保持侧躺 → 重启恢复 → 站起再坐下恢复原参数。iPad 增加横竖屏，页面无可见滚动条。

截图：[坐姿](iphone17/01-chat-sit.png)、[精细调节](iphone17/03-precision-controls.png)、[蹲姿](iphone17/05-chat-crouch.png)、[侧躺](iphone17/06-chat-lie.png)、[iPad 横屏](ipad-pro-11/09-ipad-landscape.png)、[独立 GLB 坐姿](compatibility/11-independent-glb-sit.png)。[实际模拟器录像](iphone-flow.mp4)约 166 秒，保留原速，包含测试启动、重启和系统桌面；它录自修正横屏构图前的最终 iPhone 流程，竖屏行为不受该修正影响。

engine/ 内为真实 Unity 六姿势渲染及网格边界，不是概念图。PNG、录屏、逐帧日志和完整 xcresult 留在应用仓库，不全部打进给制作方的 SDK。

motion-review.json 的镜头检查仅覆盖日志实际保留下来的**重启后恢复躺姿、转回站/坐和 iPad 旋转**，不是冒充完整流程的逐帧证据。该范围内无额外显式相机 Snap；头颈数值在已设边界内。镜头/骨骼过渡分别使用现有解析弹簧和五次平滑曲线，持续姿势切换可中途改目标。

## 发现的问题与处理

- 第一轮首尾姿势正确，但站坐转换中脚底最低到地面下约 11.85 厘米。新增编译期支撑点选择与运行时轻量内部根抬升。294 点复查最低 y=0，无超过 2.5 厘米的穿地样本；原始失败报告 transition-contact-before.json 保留。地面保护不等于脚锁定或自碰撞系统。
- 低机位露出室内/海边/示例小院的有限地板前边缘。保留原背景布局，延长前方地面，受影响场景升补丁版本；最终截图确认低机位地面延续。
- iPad 横屏侧躺时脸落在聊天状态提示后面。宽低姿势改用上方区域的完整包围盒构图，目标仍经原镜头弹簧；UI 测试等待镜头收稳并检查脸部高度，保留修正前截图用于归因。
- Unity 返回的曲线属性使用 m_LocalPosition / m_LocalRotation；导入器规范化属性名前缀和大小写再做完整轨道检查，未跳过缺轨校验。
- SwiftUI 定制面板超出类型推导时限，拆分 header/tabs/controls/panelContent 并显式标注回调类型。macOS 独立 Swift 测试可执行文件被 SIGKILL，日志不足以定因；使用系统 Swift 解释器运行同一核心测试通过，未声称问题是内存不足。
- 运行时回归工具若沿用前一套测试的较小 presentationId 会被正确拒绝；重启 Play 会话后以新状态执行既有 78 项测试通过，未放松过期消息保护。

## 当前边界

只支持作者制作的地面姿势和作者声明范围内的参数。坐椅子、躺床、台阶/坡面贴合、任意关节编辑、通用 IK、全身自碰撞、布料求解及任意自然语言运动生成尚未实现。侧躺专用身体动作只有摇头；坐/蹲可挥手、致意、摇头，缺失映射会反馈不可用而非突然站起。

骨骼过渡改善连续性，不声称程序生成的站坐转换等同于动作捕捉的完整重心/落脚运动。高精度成品仍需模型作者检查服装、体形极值、每个参数组合与专用动作。预编译支撑点降低当前姿势转换穿地风险，不能证明任意以后资源都不会穿插。

本轮依用户外出安排只更新模拟器，未给手机安装 0.11.0。workspace 保留 simulator 配置；真机后续需重新导出并构建当前 Unity 源码。模拟器功能通过不能证明真机持续 60/120 FPS，未在本轮重新测真机温度和帧率。

## 复现核心检查

```bash
.local/character-sdk-venv/bin/python -m unittest discover -s character-sdk/tools -p 'test_*.py' -v
.local/character-sdk-venv/bin/python -m unittest discover -s environment-sdk/tools -p 'test_*.py' -v
.local/character-sdk-venv/bin/python scripts/validate_characters.py
.local/character-sdk-venv/bin/python scripts/validate_environments.py
python3 scripts/export_unity_ios.py --platform simulator
```

UI 自动化用例：CharacterHostUITests/PostureFlowTests；设备 destination 选择本机 iPhone 17 或 iPad Pro 11 英寸 M4 模拟器。Unity 审查入口在 Assets/Editor/PostureReview.cs；运行时审查须在独立 Play 会话执行，避免复用另一套测试的 sequence/presentation 状态。
