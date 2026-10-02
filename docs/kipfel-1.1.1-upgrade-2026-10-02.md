# 小猫完整功能升级：Kipfel 1.1.1 PC

用户要求只保留新版小猫，将原琪宝的完整功能迁移过来。当前资源以 **Kipfel 1.1.1 PC 主 Prefab** 为准，不使用 Mobile 精简版。保持 `anime-kipfel` 身份和 `app.starry.characters.anime-kipfel` 包 ID，包版本从 2.2.0 升为 3.3.0，显示名为「小猫」。删除重复的 `anime-kipfel-v111` 预览入口；原始 ZIP 与旧转换结果留在私有目录，未改动原始用户资源。

App 版本为 0.92.0 / build 123。当前名册为 40 个角色：11 个完整对话角色、29 个本地预览角色。小猫继续属于完整对话角色；其余角色没有被改成预览模式。

## 身份、语音与数据

保留原角色 ID，而不是把旧聊天复制到新预览 ID。原音色绑定、云端角色请求、聊天与记忆归属、角色专属配乐、环境及个人偏好继续使用 `anime-kipfel`。对迁移前后 40 个集合逐项比较，除小猫的包版本更新外，现有音色、音乐、环境与默认配置一致；仅移除重复预览集合。

发现页和资料页显示「小猫」。已有角色人设、问候录音、封面和头像继续沿用，所以预制问候仍可能自称「琪宝」；这是保留原身份的昵称，没有把旧音频重新标注成不同台词。此轮没有调用图片生成、语音生成、ASR 或付费对话接口。

## 来源与实际适配

来源 ZIP SHA-256：`496789394fede7375f669c73b5c5943fb4b8870c6bac0c9d324aecdf113c7c2e`。选用 `Assets/MOCHIYAMA/Kipfel/Prefab/Kipfel.prefab`；有效几何、材质、骨架与默认形变按该 Prefab 的实际状态导出。来源锁保存本次身份和旧 1.0.3 的哈希，避免普通重建把主角色退回旧版。

| 内容 | 当前结果 |
| --- | --- |
| 模型与形变 | 完整 PC 几何，23 个蒙皮 renderer、456 个形变通道；隐藏配件也保留，按作者默认穿搭显隐 |
| 来源片段 | 核对 99 份作者片段，其中 68 份为零时长静态内容；逐项记录为可见表现、开关配对或平台辅助控制，不把片段数当连续身体动画数 |
| 原作表现 | 84 项：姿态 10、耳朵 8、尾巴 7、表情 42、手势 8、穿搭 9；加 3 项摸头反馈设置，共 87 项、7 个分组 |
| 动态表情 | 重新按作者曲线采样，包括哭泣、入睡／起床等；没有用末帧代替动态曲线 |
| 超幅度形变 | 起床 `eye_down` 原曲线超过 100%；用 1.592 倍目标差值与倒数权重保存实际位移，保持协议 0–1 且不截断曲线 |
| 待机与眨眼 | 保留作者 stand + breath 合成基线，沿用已有星夜的可见呼吸、自然眨眼、微风策略；明确区分宿主适配与作者原片段 |
| 衣发物理 | 105 段含可选袖口的骨链，33 个胶囊近似球体、5 个原平面碰撞体，保留每段的碰撞关联 |
| 物理开关 | 8 个选项映射控制袖口骨链和尾巴动作的小腿碰撞开关；恢复默认同时恢复原碰撞状态，稳定开关不会逐帧重启弹簧 |
| 旋转约束 | 五处包带／手臂扭转约束迁移为 Unity 原生 RotationConstraint，保留源路径、权重、轴向及偏移 |
| 摸头反馈 | 原 PetMode 的关闭／开心／不满映射到星夜的本机头部点击；使用原开心／不满脸，约 1.6 秒后恢复用户原表情，手动选择优先 |
| 材质 | 固定 lilToon 2.3.4，保留类型化原属性、贴图、MatCap、发光、闪光、透明与描边等；不执行角色包内的 Shader、脚本或 DLL |
| 完整功能 | 幅度口型与原 viseme、语音、对话和音乐保留，小猫不是本地预览集合 |

原 VRChat 公共 SDK 的 8 个 VRCEmote 引用、联网、自触碰权限、世界操作、上传标识和工程代码不打包。包内 `ContentsPosition` 是没有显示网格的包内物品挂点；本 App 没有给它附加物品，因此显隐辅助对象不当作可见服装按钮。尾巴与袖口的物理 helper 已转成宿主物理数据，没有按“非 renderer”静默丢弃。

## 明确的适配边界

用户提供的新旧两个版本都缺少银饰材质引用的同一张遮罩：GUID `e025416a8dd03174e8617922a4b33bda`，涉及 `_EmissionBlendMask` 与 `_GlitterColorTex`。检查来源资源清单及官方 lilToon 贴图库后仍未找到。本次仅允许这两个经过审查的缺失引用，保存原缺失身份，并沿用固定原 Shader 的空贴图／默认行为；其它缺失贴图仍拒收。没有生成替代图片，也没有宣称原包所有依赖均齐全。

物理使用星夜的有界阻尼弹簧、胶囊球体近似和角度限制，不是 VRChat PhysBone 的数值等价实现；本机点击也不等于 VRChat 的网络手部 Contacts。可见内容和作者控制已适配，不能由此声称与 VRChat 所有环境、动捕或平台行为逐帧一致。

## 验证与重建

此轮先完成转换，再对实际运行的绑定、姿态、形变、显隐、默认恢复及跨角色隔离做检查。测试期间修复了默认上装隐藏层的恢复错误，并把只适用于旧 Animation 表现的检查与 Mecanim 参数控件分开；参数控件继续由 `PortableAvatarReview` 检查，未把其它角色的零值参数当失效开关。

- 所有导入包 SDK 校验通过；SDK 单元测试 **67 项通过**。
- 来源动画 YAML 检查 **2 项通过**；自然待机四元数、首帧参考、原片段与时间保留检查 **4 项通过**。
- 新版小猫专项运行检查 **27 项通过**，涵盖 456 个形变、五约束、105 段物理、平面关联、袖口和尾巴开关、摸头与手动优先。
- 从本次 Unity 实际生成的 Prefab 核对其它 39 个发布角色的 5,728 段旧版本物理初始状态，全部仍启用；新字段没有让旧包因缺少字段而停用物理。这是导入后的状态回归，不是 39 个角色的逐项真机物理测量。
- 小猫与豆日向的 Animation 表现回归 **7,311 项断言通过**；40 角色基础导入、场景、取景和动作校验通过。
- **19 张实际求值截图**生成完成，已查看默认、笑脸与坐姿等画面；截图采用临时 CPU BakeMesh 避免单 Editor 帧 GPU 蒙皮缓存，不把冻结审查网格带入 App。
- 40 角色集合、封面 SHA／尺寸／绑定与开场资源校验通过；Swift 数据层 **283 项通过**，验证完整角色仍可路由、预览角色不能建立语音／对话请求，未发送网络请求。
- iOS 真机 Unity 导出与 Release 编译通过，0.92.0 / build 123 已安装到 iPhone 17（iOS 27.0）。手机上的数据层入口实际完成 **283 项检查**，40 个角色中只有一个 `anime-kipfel`，且仍属于 11 个完整对话角色。
- 真机正常启动进入 Unity / Metal 初始化，实际设备为 Apple A19 GPU，HDR 与 4× MSAA 生效。启动日志报告 `thermalState: Serious`；本次没有冷机帧率、持续功耗或 87 项效果逐项实机测量。
- 真机 XCUITest 在运行任何测试前遭到 XCTestManager 的 DTX 通道拒绝，Runner 因 IDE 断连退出（code 74）；这是自动化基础设施失败，不能记作 UI 测试通过。
- 模拟器首轮安装与实际新版画面显示成功，交互用例在状态检查处失败：Release 没有编译 `#if DEBUG` 下的运行状态探针，返回空字典。随后在独立模拟器构建中临时启用 `DEBUG STARRY_TEST_TOOLS` 重跑；手机 Release 安装包未添加这些探针。保留首轮失败证据，没有通过删除状态断言来规避。
- 独立 Starry Night QA — iPhone 17（iOS 26.4）模拟器完成 `testUpgradedKipfelRetainsConversationAndAuthoredEffects()`：**实际执行 1 项，0 失败、0 跳过**。发现页进入小猫后确认包版本 3.3.0、完整对话输入和 PetMode 默认；切换猫咪微笑、竖耳、卷尾、坐姿，检查分组与全部默认恢复、每步镜头不变；头部命中为 `CharacterTouchSurface`，`petReactions` 从 0 到 1，原开心脸确实选中。保存六张 App 截图及对应运行状态，已复核默认、笑脸和坐姿画面。
- 最后使用无测试参数的正常入口启动手机 App 成功。没有卸载手机 App 或清空用户数据。

这些 Editor 截图和数值检查不是手机帧率测试，也不代表 87 项表现逐项真机性能测量。

转换候选入口（需要已恢复的完整角色模板、私有源审计及新版 stage）：

```sh
.local/character-venv/bin/python scripts/upgrade_kipfel.py --output .local/kipfel-upgrade/candidate-next
.local/character-venv/bin/python scripts/upgrade_kipfel.py --output .local/kipfel-upgrade/candidate-next --apply
unity run "$PWD/unity/CharacterRuntime" --timeout 1200 -- \
  -executeMethod KipfelUpgradeReview.BuildAndReview \
  -logFile "$PWD/.local/logs/kipfel-upgrade-review.log"
```

候选先 seal 与 validate；应用时先复制完整候选，再以同文件系统 rename 替换旧生成目录，留存私有备份。`scripts/prepare_vrchat_characters.py` 的正常小猫集成入口已转到这条新版路径；`--geometry-only` 仍属于历史诊断用途。首次恢复机器仍需按技能重建审计、有效 Prefab 几何和来源动作采样；不得用伪造的 catalog stamp 跳过 Setup。

模拟器 UI 检查使用独立 DerivedData 和 QA 设备。若使用优化后的 Release 配置，须显式提供测试探针条件（正式手机安装未这样构建）：

```sh
xcodebuild -workspace ios/StarryNight-Simulator.xcworkspace -scheme CharacterHost \
  -configuration Release 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG STARRY_TEST_TOOLS' \
  -destination 'platform=iOS Simulator,id=EFA3B59D-3939-4659-B60B-123516393F43' \
  -derivedDataPath .local/build/KipfelSimulatorDerivedData \
  '-only-testing:CharacterHostUITests/VrchatCharacterTests/testUpgradedKipfelRetainsConversationAndAuthoredEffects()' \
  -parallel-testing-enabled NO test
```

本机详细证据：`.local/kipfel-upgrade/runtime-review.json`、`package-validation.log`、`sdk-tests.log`、`model-review-core.log`、`phone-core.json`、`phone-runtime.log`、`device-ui.log`、`phone-final-launch.json`、`simulator-ui-probes.xcresult` 与 `simulator-ui-probes-attachments/`，以及 `.local/logs/kipfel-v111-device-export.log` 和 `docs/verification/vrchat-performance/render/`。原包、转换模型、曲线、截图、签名与安装产物保留本机，不提交公开仓库。
