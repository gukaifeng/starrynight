# 第六批：意可蕾与 Sio 本地预览

2026-10-02 在剩余来源中复核两项此前被转换器阻挡的角色。意可蕾 1.1.1 和 Sio（来源未标版本）已加入 `previewOnly` 名册，图片取自各自来源目录；没有调用百炼图片、音乐、音色或对话 API。受限模型、图片和转换包仅保存在本机，不公开提交。

意可蕾的人物贴图完整。原作手持 Takt 的 `Fresnel` / `Cone` 光效使用未随来源提供的专用 shader；Takt 屏幕有 Unity 运行时 RenderTexture。仅对这三个明确的道具效果做本地预览降级，人物面部和衣服没有套用未知 shader。两处 `_ShadowBorderMask` 缺失作为可审计的阴影细节限制保留。两个超过 128 UTF-16 单位的 `SpatialScreen` 子物体初始处于关闭状态，便携表现默认列表按源状态不启用它们，不改动原作路径。Unity 截图 `.local/vrchat-batch/render/eku.png` 人物画面可用；72/72 原作控制可复位，62 项产生可见差异。屏幕和道具光效尚不能宣称与 VRChat 原作相同。

Sio 的 Material Variant 父材质并非缺文件，而是来源包内的 Unity Material `.asset`。转换器现在只在该文件明确含 `Material` class 21 时接受它，仍拒绝非材质 `.asset`；内衣 `_OutlineTex` 缺失作为非主体描边限制记录。Unity 截图 `.local/vrchat-batch/render/sio.png` 人物画面可用；38/38 原作控制可复位，37 项产生可见差异。Sio 的原作默认穿着是内衣，本地预览如实展示原始状态。

XCP seal/validate、隔离 Unity 渲染和控制复位已通过；模拟器导出校验通过：20 个角色和 20 个隔离集合；11 位原有可聊天角色的音频仍通过校验。iPhone 17 Debug App 构建成功。`MarketplaceUITests/testThirdLocalPreviewBatchOpensWithoutComposer()` 从发现搜索逐个打开意可蕾和 Sio 的资料与模型预览，确认没有 AI 输入框，58.982 秒通过，0 失败。iPhone 17 真机已签名安装，并由 `devicectl` 返回启动成功，App 版本 0.84.0 / build 114；未逐个在真机上手动测试这两位角色，真机帧率未测。隔离截图和按钮复位不代表真机帧率或专用道具特效已完整迁移。
