# 第四批：本地模型预览

2026-10-02 将爱莉、Marycia、美云、米露缇娜、信浓加入本地名册。这一批的目标是先让用户在 App 内看实际模型效果，因此角色被显式标记为 `previewOnly`：使用各来源目录自带封面，保留模型、骨骼、作者控制和物理适配；不生成角色语音、音乐、图片或 AI 对话，也不会为它们请求百炼。原有 11 个可聊天角色不变。

来源档案、选中 Prefab、SHA-256 和受限资产路径记录在本机 `.local/vrchat-batch/plan.json` 与各 XCP 的 `source-meta.json`。这些资产只在本机安装，公开仓库仅提交名册与转换流程，不提交原包、贴图、模型或封面。

五个候选均通过 XCP seal/validate、Unity 隔离渲染和逐项作者控制的 Reset 复位：爱莉 43/43、Marycia 27/27、美云 40/40、米露缇娜 41/41、信浓 44/44。可见状态变化分别为 40、27、30、41、41 项；剩余按钮多为默认手势/原作平台专用状态，不能宣称在 App 中都有可见效果。渲染图、控件明细保存在 `.local/vrchat-batch/render/<role>.png` 与 `<role>-controls.json`。缺失的少量非主体描边、阴影和 MatCap 贴图逐条保存在私有 XCP 的 `source-meta.json.previewShadingLimitations`；它们只被允许进入本地预览，尚未通过与 VRChat 原版的逐像素材质比对。

本批时米露菲虽封包成功，Unity 遇到动态 RenderTexture 缺失，暂未激活；后续已作为屏幕功能降级的本地预览加入[第五批](preview-05.md)。白爪花的原作物理碰撞器半径超过宿主安全范围，不能直接裁断原作物理，未激活。Azuki、Hikarun、Nemesis、Perula 等重新检查后仍缺可达动作；Rindo 只有衣服没有本体。它们没有拿空动画冒充可用按钮。更多逐项原因保留在 [整库结果](library-status.md) 和本机 `package-status.json`。

模拟器导出后，`check_export_content.py` 验证 16 个角色和 16 个相互隔离的集合；11 个正式角色的开场 PCM 校验通过，5 个预览角色没有开场语音或对话请求。iPhone 17 模拟器的开场/预览离线检查 219 项通过，首个正式角色语音开始播放约 0.26 秒。`MarketplaceUITests/testImportedLocalPreviewDoesNotOpenAIComposer()` 实际经过发现搜索 → 爱莉资料 → 查看模型，23.84 秒通过、0 失败；预览页实测展示 Unity 模型和“模型预览”提示，没有聊天输入框。截图保存在 `.local/checks/Preview04-attachments/`。

验证边界：Unity 截图是隔离场景画面，XCP seal 是静态包校验；模拟器 UI 流程只覆盖爱莉的完整页面路径，另四位有隔离渲染/控制复位和 App 目录静态校验。它们都不是 iPhone 真机帧率或 VRChat 原版能力全等的证据。
