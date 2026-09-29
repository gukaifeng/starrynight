# 窗口与页面保持角色取景 · 0.28.1 / 45

2026-09-29，iPhone 17 / iOS 26.4 模拟器。规则是打开、关闭和切换界面不触发角色取景调整；用户主动调整镜头仍有效。方案见 [页面与角色取景分离](../../design/2026-09-29-stable-panel-framing.md)，最终构建／安装状态见 [result.json](result.json)。

## 竖屏实际过程

`testPanelsKeyboardAndTabsKeepThePortraitCamera` 通过，耗时 **145.286 秒**，覆盖：

- 从正常发现页打开角色资料并进入会话。
- 会话资料卡、定制首页以及外观、空间、取景、性格声音、音乐、聊天显示、记忆、聊天资料八个子页。
- 面容／身形／造型／空间／姿势分类切换，以及调整聊天区域高度。
- 输入草稿、弹出和收起键盘、展开弹窗、滑动关闭、返回按钮和窗外关闭。
- 消息／发现／创建／我的四个底栏页面再回首页，保留同一角色与镜头。

实际 Unity 相机采样覆盖 **134.20 秒、4,871 个渲染样本**。全部样本的相机位置 XYZ、距离、俯仰、朝向、FOV、取景范围、大小、构图区域和渲染区域都不变；运动样本数为 0，新增切镜数为 0。包含弹层动画中间阶段，避免只比首尾忽略中间缩放。[逐字段统计](camera-samples.json)

原始采样保留在 `.local/checks/panel-camera-portrait-motion.jsonl`，完整 UI 结果为 `.local/checks/Starry-Panel-Camera-Portrait-Verified.xcresult`。可重新检查：

```sh
python3 scripts/verify_panel_camera.py .local/checks/panel-camera-portrait-motion.jsonl \
  --output docs/verification/panel-camera-stability/camera-samples.json
```

## 横屏与主动调整

`testLandscapePanelsAndKeyboardKeepCamera` 通过，耗时 **70.590 秒**。完成设备旋转适配后，打开／关闭空间和取景面板、弹出键盘均保持既定相机；主动选择全身、恢复推荐仍改变取景，关闭窗口保持调整结果。

`testExplicitFramingPersistsAcrossPanels` 通过，耗时 **48.192 秒**。用户主动选择全身、110% 大小、右转 20° 后，打开外观页、切换身形／面容／空间分类、返回会话，均保留这套取景。

三项实际 UI 用例共 **264.068 秒、0 失败**。原始报告为 `.local/checks/Starry-Panel-Camera-Portrait-Verified.xcresult`、`.local/checks/Starry-Panel-Camera-Landscape.xcresult` 和 `.local/checks/Starry-Panel-Camera-Manual-Verified.xcresult`。UI 状态断言覆盖两个方向；连续逐帧采样统计来自上述竖屏流程。

## 截图

| 场景 | 实际画面 |
| --- | --- |
| 原始会话与资料卡 | [会话](screenshots/01-conversation.png)、[资料](screenshots/02-profile.png) |
| 外观、空间、取景 | [外观](screenshots/panel-appearance.png)、[空间](screenshots/panel-space.png)、[取景](screenshots/panel-framing.png) |
| 其他定制子页 | [性格声音](screenshots/panel-profile.png)、[音乐](screenshots/panel-music.png)、[聊天显示](screenshots/panel-display.png)、[记忆](screenshots/panel-memory.png)、[聊天资料](screenshots/panel-history.png) |
| 键盘与窗口变化 | [键盘](screenshots/03-keyboard.png)、[展开窗口](screenshots/04-expanded.png)、[菜单返回](screenshots/05-returned-home.png) |
| 主动调整与横屏 | [保留手动取景](screenshots/06-manual-framing-kept.png)、[横屏键盘](screenshots/07-landscape-keyboard.png)、[主动恢复推荐](screenshots/08-explicit-reset.png) |

每张专项截图有同名 `-runtime.json`，供直接比较真实相机状态。角色动作和表情仍正常运行，因此不能用面部像素完全一致代替相机状态检查。

## 检查过程中的问题

关闭没有修改的取景页后，旧调试入口会把 JSON 替换成文字摘要；此前靠随后自动发出的镜头命令补回状态。取消这些多余命令后，测试读不到 JSON。现在 UI 测试模式让运行时事件独占诊断值，发布版本继续使用普通辅助功能摘要，不伪造相机数据。早期失败流程中的实际采样也保持稳定。

另一次底栏返回失败来自旧 `--preview-human` 入口没有登记当前选中角色，返回首页去了默认角色；正式流程本来就会登记选择。专项改用“发现→资料→会话”的真实入口，最终覆盖同一会话跨全部菜单返回。原始失败报告保留，不计入最终通过结果。

横屏短侧栏的默认 `swipeUp()` 未能滚到目标入口，单纯增加次数仍不稳定；自动化改为沿滚动区右侧执行明确的竖直拖动，最多十次，找到入口即停止。修正仅作用于测试驱动，产品滚动方式不变。拆分主动取景与横屏用例，分别取得完整通过结果。

没有修改 Unity 场景／模型或重新导出，不新增 iPad 测试，也不把本次相机采样当作真机 FPS 测量。实际旋转设备仍适配屏幕比例，用户主动选取景／大小／朝向、恢复推荐、调整姿势或切换角色仍可以产生相应变化。

## 构建与安装

Simulator Debug 与 Device Release 编译通过，真机包 `codesign --verify --deep --strict` 通过。手机一次无线安装成功，设备回读 **星夜 0.28.1 / build 45**；自动启动被 iOS 以 `Locked` 拒绝，不等待解锁或重复安装。手机解锁后可直接打开新版；本轮交互验收来自模拟器，未宣称真机实测完成。模拟器以正常参数启动，Xcode 工作区保留 device / Release，原 App 标识及资料不变。

[正常启动画面](screenshots/09-normal-launch.png)与专项截图保留在本目录；构建、安装及启动结果见[result.json](result.json)。
