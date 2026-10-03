# 情感陪伴动作库 v3 验证

版本：0.99.0 / 130，2026-10-03。完整目录与设计取舍见[48 组设计](../../design/2026-10-03-emotional-gesture-library.md)。本次为宿主实验层升级，保留十个原有组合 ID，新增 38 个；复用角色原作的十类校准表情，不声称所有角色有 48 个不同的原作脸部资产。

## 覆盖与幅度

- 当前发布名册 16 个角色，48 个组合，分别以 60 / 120 Hz 数值采样，共 1,536 组、11,587,714 项断言，最终源码复核通过。检查有限旋转、根与腿脚不变、自然恢复、中途关闭、解绑、原作姿势优先和语音开始/停止。单一 JSON 另核对八类各六组、48 个 ID 与 48 套不同解剖角度参数。
- 峰值附加单关节角为 25–68°，最大相邻采样角变化约 1.846°；较大的角来自前臂屈曲，不是头颈扭转。头颈合计仍限制俯仰 -18…24°、左右 -26…26°、侧倾 -17…17°。
- 与上次相同青柠角色的数值记录比较，挥手问好峰值从 38° 增至约 67.62°，开心回应 22° → 51°，温柔鼓励 31° → 62°。不能用这些单关节倍率代替整个人物观感；默认衣装画面和 App 预览分别检查。
- 新编排增加预备、躯干/头/肩臂错峰、不对称和收势，使用 C2 连续曲线；原作 Animator、口型、根位置、相机和腿脚均不由新增层写入。

## 实际画面与原生交互

- Metal Editor 实际渲染戚风、Hikarun、草莓、青柠，八个代表动作分别捕获中性与峰值，共 64 张独立画面。已检查挥手、舒展、欢呼、害羞等峰值：肩臂方向、前臂屈曲和头颈范围合理，检查过的默认穿搭未见明显穿插。蒙皮冻结后渲染，避免离线审图读取旧帧；不将静态图称作动态录屏。
- iPhone 17 模拟器实测使用真正 Unity 桥接、骨骼和回执。语音联动测试播放已有首句 PCM，等待实际 `speaking`、自动动作和可见幅度，然后验证播放结束收回；该测试通过（30.102 秒），不调用付费 AI。
- 手动回归包含原有十组、八类新增代表、自然结束/停止、开关、三个角色切换，以及关闭新增层后的原作手势和源表情恢复。修复搜索焦点后受影响用例重跑通过：1 个测试、0 失败，336.592 秒。结果 `.local/checks/HostEmotion-v099-Preview-Final.xcresult`；真实 PCM 语音用例在 `.local/checks/HostEmotion-v099.xcresult`，该旧测试包整体因已修复的搜索问题失败，不能将整包描述为通过。

- Unity 模拟器/设备分别导出成功，两个目标的生成 C++ 均确认包含最终语音起步窗口。设备 Release 签名构建成功，`codesign --verify --deep --strict` 通过；设备 App 元数据确认 `com.gukaifeng.xiaoban.dev`、0.99.0 / 130。

- iPhone 17 无线安装成功，安装回执 `.local/checks/device-install-v099-wireless.json`；设备应用列表回读确认 0.99.0 / 130（`.local/checks/device-app-v099-installed.json`）。随后远程启动返回 `Locked`，不能把安装成功称作已进入真机会话或已测过真机帧率。解锁手机后可直接打开新版本。

## 发现的问题与处理

1. **语音与情绪事件相邻但异步。** 原生语音 beat 排程表情任务后马上通知 speaking；若马上选配身体动作，可能先拿到中性意图。增加仅作用于动作层的 120 ms 情绪收集窗口，音频不等待。窗口内的表情 cue 合并后选配，结束时释放并丢掉最新队列；实际 PCM 回归通过。
2. **原作源片段页键盘遮挡结果。** 第一轮原生回归已完成组合预览和独立开关，却在旧源表情页点击结果时失败。给该搜索框增加标准“搜索”键和焦点收回，保留搜索文本；修复后重跑受影响的交互用例，不将首次失败写成全套通过。
3. **48 组编排与旧角色包兼容。** 校准构建仍产出十类原作脸部基底，48 组目录由 App 宿主解析。此次升级不要求重建或重传旧 OSS 角色包；原作资产变更仍须按角色发布流程更新包。
4. **审图与导出隔离。** 数值检查使用无图形 Editor，画面审查使用独立 Metal Editor；关闭审图 Editor 后分别导出模拟器与设备，避免已有的图形回调/构建进程问题。

## 可重现与资源边界

```sh
unity run "$PWD/unity/CharacterRuntime" --timeout 1800 -- \
  -nographics -buildTarget iOS \
  -executeMethod HostEmotionMotionReview.RunNumerical \
  -logFile "$PWD/.local/logs/host-emotion-v3-review-final.log"

# 数值 Editor 完成后，以独立有图形进程审图
unity run "$PWD/unity/CharacterRuntime" --timeout 1800 -- \
  -buildTarget iOS -executeMethod HostEmotionMotionReview.CaptureGallery \
  -logFile "$PWD/.local/logs/host-emotion-v3-gallery.log"

zsh scripts/test_companion.sh \
  99F5FAC6-A73A-4C59-A723-D57D648B342E \
  'HostEmotionMotionTests/testPilotPreviewsSwitchAndOriginalControls()' \
  HostEmotion-v099-Preview-Final
```

实际报告、受限角色截图和 XCTest 结果留在本机 `.local/checks/`，日志在 `.local/logs/`，不随公开仓库分发。宿主自编参数与代码可以提交；没有调用图片模型，也没有为动作增加对话/语音请求。

## 验收边界与撤回

60 / 120 Hz 是动画数值采样频率，不是手机实测渲染帧率。四角色审图与三角色原生交互不等于所有换装、所有相机角度都无碰撞；本次不引入走跑、接触拥抱、手摸脸等需要额外接触或足底 IK 的动作。

入口为浮动开发者图标 → 动作实验。手动组合开关沿用旧偏好；“随语音联动 · 实验”默认关闭，需要主动打开。关闭身体与表情组合可撤除新增叠加；原作动作、口型、眨眼、风与衣物物理继续由原有机制运行。代码标记 `HOST-EMOTION-EXPERIMENT v3`，原始模型与用户记忆不变，独立回退本次提交也不影响颜色定制、语音、下载等其他功能。
