# 二次元角色扩充验证 · 星夜 0.28.0 / 44

2026-09-29，iPhone 17 / iOS 26.4 模拟器。新增小光、小诗、晴川，原有四个角色保留。结果索引为 [result.json](result.json)，资源和动作来源、实现取舍见 [方案](../../design/2026-09-29-anime-ensemble.md)。

## 实际通过的范围

| 检查 | 结果 |
| --- | --- |
| 资源及动作回归 | 2 个测试通过：源动画坐标归一化、三包动作边界、腿部稳定、四元数、网格和次级摆动数据 |
| 原有集合及存储检查 | 59 条通过，覆盖角色隔离、游客额度、搜索、身份、隐私和迁移 |
| Unity 场景与角色绑定 | 7 个角色、6 个环境通过；角色集合完整性为 7 个集合、28 个限定音频选项 |
| 新角色实际操作 | 70.419 秒通过，三个角色分别搜索、打开资料、进入会话、首句朗读、触头摇头、聊天请求抬手 |
| 动作与外观隔离 | 103.248 秒通过，另外六种动作、解锁拖动、发色保存、角色切换及恢复 |
| 实际引擎画面 | 3 角色 × 9 动作 × 3 阶段，共 81 张；另有左右侧面与背面，共 9 张 |
| 构建 | Simulator Debug 与 Device Release 通过，真机产物严格验签通过 |

UI 测试从真实按钮、输入框和坐标触摸进入，没有用直接调用引擎函数代替用户操作。三个角色的首句检查实际 `voiceMotion:playing`，头部动作检查原生触摸计数与 `No`，聊天动作检查当前角色收到的动作及镜头状态。新角色当前仅声明站立会话动作。

模拟器已用正常启动参数打开，保留原 App 流程。手机一次无线安装成功，回读星夜 **0.28.0 / 44**；随后一次自动启动被系统以 **Locked** 拒绝，未重试或等待解锁。用户解锁后可直接打开现有星夜；安装没有清除原资料。Xcode 保持 device / Release。详见 [result.json](result.json) 的 device 项；安装成功不代表本轮完成了真机动作或帧率测试。

## 实际截图

| 小光 | 小诗 | 晴川 |
| --- | --- | --- |
| [会话与朗读](simulator/anime-vita-conversation.png) | [会话与朗读](simulator/anime-shino-conversation.png) | [会话与朗读](simulator/anime-fumiriya-conversation.png) |
| [触头回应](simulator/anime-vita-head-touch.png) | [触头回应](simulator/anime-shino-head-touch.png) | [触头回应](simulator/anime-fumiriya-head-touch.png) |
| [抬手招呼](simulator/anime-vita-hello.png) | [抬手招呼](simulator/anime-shino-hello.png) | [抬手招呼](simulator/anime-fumiriya-hello.png) |
| [全动作及侧后面](renders/anime-vita-contact-sheet.jpg) | [全动作及侧后面](renders/anime-shino-contact-sheet.jpg) | [全动作及侧后面](renders/anime-fumiriya-contact-sheet.jpg) |

[小诗更改发色后返回](simulator/anime-shino-return.png)、[已保存发色的选中状态](simulator/anime-shino-saved-hair.png)、[小光仍保留原配色](simulator/anime-vita-independent.png)。每张模拟器专项截图配有同名 `-runtime.json`，保留角色、动作、镜头、视线和原生手势状态。

## 修复与测试边界

- 首次动画导入忽略 VRMA 源骨架轴向，实际渲染出现腿折到头顶。使用 pixiv three-vrm 官方归一化关系修正，加入腿部静置偏差与动作端点回归。
- 默认白色参数覆盖了原作者深色发色。修正线性颜色转 sRGB 与参数初值，重建所有新角色缩略图和头像。
- 第一轮界面测试误期望切回角色仍保持手势解锁；平台本来就会在进入不同会话时恢复锁定。保留该行为，改为验证真正持久化的发色选项；顺便补上颜色选项的辅助功能选中状态。
- Xcode 首次方法级过滤执行了 0 条，虽然返回成功，未计入通过结果。补上方法名的 `()` 后实际执行并通过；驱动脚本现在遇到 0 条已完成测试会明确失败。
- 后视图初次被房间背墙遮挡。仅在编辑器检查用的侧后截图中隐藏环境几何，重新渲染；没有改变交付场景。

关键证据保留在 `.local/checks/Starry-Anime-Ensemble.xcresult` 和 `.local/checks/Starry-Anime-Appearance-Run.xcresult`。第一份原始结果含上述错误断言的失败，另一条三个角色流程已通过；第二份为修正后的外观流程，最终两个不同用例均通过。

这是代表动作阶段和实际交互的检查，不是所有动作混合、机位、外观组合的完整碰撞证明。次级摆动是受限弹簧链，仍可能在极端情况下有细微相交。动作资源 30 Hz 采样由 Unity 连续插值，沿用 App 的 60/120 Hz 请求策略；本轮没有真机持续帧率或热稳定性数据，不能用模拟器结果宣称锁定 120 FPS。三个角色暂共用已有离线中文音色，未制作独立声线；本轮未测试 iPad。
