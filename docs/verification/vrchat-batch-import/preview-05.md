# 第五批：米露菲与雫本地预览

2026-10-02 在全部 40 条来源逐项重查后，将米露菲（Milfy 1.5.0）和雫（Shizuku，来源未标版本）加入 `previewOnly` 名册。封面使用各自原目录图片，不产生、请求或打包百炼 AI 图片、音乐、音色、对话；预览页没有聊天输入框。原始资源仍保留在来源目录，封包和图像仅在本机，公开 Git 只提交源代码和元数据。

米露菲的原作 `SmartPhone_Screen` 材质引用 Unity 运行时 RenderTexture，它是手机屏幕动态画面而不是可打包图片。只对这个明确标识的道具屏幕使用预览降级，人物主体不受影响。隔离 Unity 实际截图 `.local/vrchat-batch/render/milfy.png` 已审查，41/41 作者控制可以复位，37 项产生可见差异。未来若需要手机屏幕效果，须单独实现实时渲染目标，不能把空白文件当图片。

雫的作者提供 lilToon 材质包与角色本体，已合并审计；缺少的是手表 LCD 和界面道具的专用 shader。只允许这六个明确材质名称使用本地预览 fallback，不泛化到人物皮肤、头发和衣服。Unity 截图 `.local/vrchat-batch/render/shizuku.png` 显示角色完整，但有细绿色线条，用户预览时需知晓这一差异。40/40 作者控制可以复位，40 项产生可见差异。正式发布前仍需解决专用 shader/线条问题。

本轮同时重试其余可选来源：40 条来源中 39 条存在完整本体，龙胆目录仅有服装。最终 16 条通过 XCP 封包，23 条仍因可达原作动作缺失、主体纹理、材质父级、构建期控制器或特殊物理/动态能力未完成而停在待审状态；没有用空动画、别的角色资源或生成内容补位。逐角色原因见 [整库结果](library-status.md) 以及本机 `.local/vrchat-batch/package-status.json`、`inspection-status.json`。

iOS 模拟器导出校验通过：18 个角色、18 个隔离集合，11 个原有可聊天角色音频及开场素材仍匹配；iPhone 17 Debug App 编译成功。`MarketplaceUITests/testSecondLocalPreviewBatchOpensWithoutComposer()` 在 iPhone 17 模拟器逐个搜索米露菲、雫，进入资料和模型预览，确认没有 AI 输入框，54.264 秒通过，0 失败。iPhone 17 真机已签名安装并通过 `devicectl` 启动，App 版本 0.84.0 / build 114；设备上尚未逐个操作两位角色，真机帧率未测。Unity 隔离渲染不能代表真机帧率或 VRChat 功能全等。
