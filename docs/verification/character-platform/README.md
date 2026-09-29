# 角色平台 v1 验证记录

本目录保存小伴 0.9.0 / build 18 的角色标准化与独立模型导入证据。最终验证于 2026-09-28 完成；手机已断开，按用户安排使用模拟器，不等待真机。

## 最终结果

| 检查 | 结果 |
|---|---|
| SDK 契约、资源、恶意输入与升级正反例 | 21 项通过 |
| 四角色清单及资源预检 | 全部通过 |
| Unity 实际 Play Mode 调度、隔离、取消、回退及形变量程 | 78 项断言通过 |
| 独立 `.xcp` 导入命令、绑定、目录和缩略图生成 | 通过 |
| SDK 解压至独立临时目录后的示例校验 | 通过 |
| iPhone 17：独立包、外观、动作、安慰/庆祝/跳舞及旧角色 | 通过，37.375 秒 |
| iPhone 17：视线、直接手势、面板及动作回归 | 通过，48.035 秒 |
| iPad Pro 11 英寸 M4：独立包和语义对话 | 通过，37.240 秒 |
| iPad Pro 11 英寸 M4：实际离线语音播放与停止 | 通过，14.937 秒 |
| Unity simulator / device 导出及目录哈希一致性 | 均通过 |
| 真机 Release 编译、版本 0.9.0 / 18、深度严格验签 | 通过；本轮未安装到断开的手机 |

最终截图见 [iPhone 17 开心回复](iphone17/04-joy-reply.png)、[iPad 开心回复](ipad-pro-11/04-joy-reply.png)，各目录还保存动作、外观、安慰、跳舞和旧角色画面。最终回归结果是 `Character-Platform-Phone-3.xcresult` 和 `Character-Platform-iPad-2.xcresult`；早期流程通过但画面异常的轮次不算最终验收。

机器可读结果见 [results.json](results.json)。真机包保存在 `.local/build/DeviceDerivedData/Build/Products/Release-iphoneos/CharacterHost.app`；当前 workspace 保持 device 配置，普通 iPhone 17 模拟器使用最终 Debug 构建。

## 已确认的边界

- 角色包为构建时导入，App 没有手机内在线下载/热更新入口。
- 四角色包含三个旧美术适配器和一个独立 GLB 包；新包不需要新增 Swift 角色分支或专用动画代码。
- 对话仍是本地情景库；语音为已有本机离线引擎。当前音频只提供幅度，并非准确逐音素 TTS。
- 模拟器与引擎检查不能证明持续真机 60/120 FPS。

## 真实发现与处理

1. **粒子模块依赖**：此前工程没有 Particle System 内置包。新增受控星光/爱心预设后，首次 C# 编译报缺 `UnityEngine.ParticleSystemModule`。通过 Unity PackageManager 补齐 `com.unity.modules.particlesystem` 后编译通过。
2. **材质属性差异**：GLB 导入器的主色字段是 `baseColorFactor`，旧 URP 材质是 `_BaseColor`。最初绑定验证正确拒绝了错误字段。源包改为标准 `baseColor`，由引擎映射；外部包不再依赖 Shader 内部命名。
3. **morph 量程差异**：首轮模拟器截图发现示例角色眉眼被异常拉长。实际读取显示旧角色满量程 100，glTFast 导入示例为 1。修复表情、口型、外观三条通道，统一把 0–1 标准权重乘以各 mesh 自身的 frame weight。增加四角色真实 blendshape 回归，保留首轮日志用于解释错误，不将其当成功截图。
4. **观测事件时序**：测试依赖短暂 `actionStarted.action`，会被随后合法的角色回执覆盖。状态增加持续可读的 `lastAction` / `activeAction`，用于区分历史命令和当前播放状态；不通过增加测试等待时间掩盖问题。
5. **图示工具环境**：Mermaid CLI 默认寻找未下载的 headless Chrome。改用本机已有 Google Chrome 的 Puppeteer 配置，架构图与时序图均通过真实渲染；没有为画图再安装浏览器。
6. **防止资源路径和通道冲突**：额外限制 thumbnail 为纯资源标识、禁止 neutral 表情 ID 被占用、基础色使用标准字段，检查持久化 morph 与临时表情/口型互斥；验证目录及 UI 标识不重复。

7. **带缩放骨架的动作取景**：虽然流程测试已通过，逐图检查仍发现开心动作把房间和模型缩到很小。独立 GLB 手部节点带 100 倍源缩放，原有 `BakeMesh()` 的结果又经过 TransformPoint，重复计入了缩放。按 Unity 6 的 `BakeMesh(mesh, true)` 语义补偿 Transform scale，并在导入时增加“动作范围不得超过中立范围 6 倍”的拒收检查，模拟器增加取景目标范围断言。由此保留视觉审查作为自动化之外的必要步骤。[Unity 6 BakeMesh API](https://docs.unity3d.com/ja/6000.0/ScriptReference/SkinnedMeshRenderer.BakeMesh.html)。

## 自动化证据

- `sdk-tests.txt`：Python SDK 正反例测试输出。
- `package-preflight.json`：全部内置及独立包的资源/声明预检。
- `engine-review.json`：实际 Play Mode 执行的事件隔离、取消、优先级、回退及 morph 量程检查。
- `import-command.txt`：真实 `.xcp` 导入结果。
- `standalone-kit-validation.json`：完整 SDK 解压后独立校验结果。
- `results.json`：最终模拟器用例、版本及构建/验签状态。
- `phone-first-run-events.jsonl`：首轮失败保留记录，含修复前的角色事件；不是最终验收结果。

检查不是美术质量的自动认证。动作中的布料/头发穿插、表情审美、移动设备温升仍须实际视觉和设备验收。
