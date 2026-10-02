# 第七批：独立新版小猫与外观预览

2026-10-02。用户要求保留 `anime-kipfel` 1.0.3，并把来源目录的 1.1.1 作为 `anime-kipfel-v111` 独立角色，待人工比较后再决定是否删除旧版。新增 Azuki、Cornet、Fiona 外观预览；四个角色均使用原包模型及作者提供的封面，不调用 AI、图片、语音或音乐接口。

四包通过 XCP seal/validate 和 Unity 隔离实际渲染。`render/{kipfel,azuki,cornet,fiona}.png` 为私有渲染证据，`*-controls.json` 绑定各 manifest SHA。原作控制器依赖未齐，这批的 `visualOnly=true`、原作控制数为 0；不可将空控制列表宣传为已适配原作动作。站立用作者已有 Idle 或显式宿主站姿适配。源档案、完整转换数据仍在私有目录，预览裁减不回写原始文件。

Azuki 原作外套/袖套在当前缺服装姿态的预览中呈悬空 T 姿。仅预览包隐藏 `Wear_Outer_Hoodie`、`Wear_Outer_TailSocks` 和 `Wear_Inner_ArmWarmers`，重渲染后双臂正常；完整服装仍保留在原始档案与转换结果。该外观与原作完整造型并不等价。

首轮 iOS 模拟器导出被重复显示资源 `Anime_kipfel` 拒绝。新版改用独立 `Anime_kipfel_v111`，重新封包与 Unity 复核后，24 角色目录校验、模拟器 Unity 导出和 Xcode Debug 编译通过。iPhone 17 模拟器 `MarketplaceUITests/testVisualPreviewBatchKeepsBothKipfelVersions()` 通过：四个新角色都能进入本地模型预览，旧版小猫仍在发现页；预览无 AI 输入框。本测试不证明真机帧率或原作动作可用。

真机安装、其他 17 个视觉候选的渲染与 App 集成另行记录，未完成前不得标为全库已交付。
