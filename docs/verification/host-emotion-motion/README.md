# 附加情绪动作试验验收

> 本页保留 0.69.0 的历史验收。0.94.0 的十组与原作片段库见[片段库验收](../source-motion-library/README.md)。当前 0.99.0 已升级为全部 16 个角色、48 组通用表情与身体组合，并提供默认关闭的实验语音联动，见[v3 验证](../host-emotion-motion-v3/README.md)。

对应版本：0.69.0 / 96。范围、入口和完整撤销点见[设计记录](../../design/2026-10-01-host-emotion-motion.md)。本记录区分计算检查、实际画面、App 交互和真机运行。

## 已完成的 Editor 检查

- 青柠、望、小梅，7 种动作，分别以 60 / 120 Hz 采样，共 42 组，222,677 项断言通过。
- 全部 11 个发布角色都检查了白名单隔离：只有上述 3 个挂载校准数据，其他 8 个拒绝附加动作请求。
- 检查真实 Animator 评估后的骨骼：有限值、双脚固定、根位置/旋转/缩放不变、结束回归、中途关闭、操作优先、望的原作姿势优先、解绑清除。
- 开关关闭后仍能选择原作 `gesture-left-2`；新增层不修改原作 Animator 参数。已有 AI 表情的 `ai.intent` 能映射到新增动作。
- 60 Hz 最大单帧关节角变化约 0.806°（青柠、望）及 0.725°（小梅）；最大附加单关节角分别 26° / 26° / 23.4°。这是动画采样结果，不是手机渲染帧率。
- 对每个动作保留中性与动作中的 CPU 蒙皮图，检查上身形变、手臂方向及默认衣装。图片和原始报告留在 `.local/checks/host-emotion-motion/`，不公开角色资源。

执行入口：

```sh
unity run "$PWD/unity/CharacterRuntime" --timeout 1200 -- \
  -buildTarget iOS -executeMethod HostEmotionMotionReview.BuildAndReview \
  -logFile "$PWD/.local/logs/host-emotion-review.log"
```

仅运行校验/渲染可调用 `HostEmotionMotionReview.Run`。渲染后应关闭 Editor，再新进程导出，避免项目已记录的 URP 缩略图/构建回调崩溃问题。

## 发现的问题与处理

1. **左右手骨名不等于导入坐标正负。** 初始肩臂外展方向在导入坐标中反向，表现为手臂向身体内收。改用实际关节相对胸部的位置决定外侧，前臂铰链轴也从实际手腕方向建立。加入舒展峰值时两手间距必须增加的检查。
2. **离线截图污染。** 测试最初只销毁克隆角色上的 `ViewerCharacter` 组件，留下渲染对象，导致后续截图出现多个角色。改为销毁整个克隆 GameObject，隔离渲染层，重新生成全部截图。污染截图不作验收依据，不属于 App 中的角色切换问题。
3. **预览状态更新。** 新动作不能只返回“请求成功”就让界面一直认为在播放。增加有限次数的可见动作与结束通知，不逐帧发送 JSON，预览标记能收回。
4. **帧内分配。** 原作姿势优先级参数在绑定时转换为 hash/type/初始值缓存；逐帧路径不做 LINQ 查找或创建捕获闭包。

## App 与设备验证

- iPhone 17 模拟器 `HostEmotionMotionTests`：1 个端到端测试、0 失败，156 秒。实际执行七种预览、自然结束、手动结束、三角色切换、开关和关闭后原作手势，使用真实 Unity 桥接与引擎回执。
- 模拟器与设备的 Unity 导出完成，原生 Debug 编译成功。App 截图在 `.local/checks/host-emotion-motion/ui-captures/`，测试包 `.local/checks/Host-Emotion-v069.xcresult`。
- 上述自动化禁用付费 AI 调用；AI 匹配通过原作表情意图映射和同一个现有 `applyAIVisual` 入口接入，没有为动作增加额外网络请求。本次没有重测在线模型服务的回答质量。
- `simctl recordVideo` 返回 `SimRenderServer` 错误，未交付录屏；保留 XCTest 截图与 App 内可重复预览，不能把静态截图描述为视频。

- 原有琪宝、豆日向、戚风、卡琳的切换、原作手势与恢复默认回归通过：1 个测试、0 失败，77 秒，结果为 `.local/checks/Host-Emotion-Legacy-v069.xcresult`。这轮使用最终 iOS 源码重新编译。
- Release 真机签名编译通过，`codesign --verify --deep --strict` 通过，确认包版本 0.69.0 / 96。
- iPhone 17 安装成功，设备回执为 `.local/checks/host-emotion-motion/phone-install.json`。随后尝试启动返回 `Locked`：手机要求密码解锁，故未声称已在真机进入会话或测过真机帧率。用户解锁后可直接打开已安装的新版本。
- 导出日志中的 16 条 `Mtl_VertexOut` 诊断也存在于此前批次导出；本次未修改 Shader。两目标导出、原生构建均成功，三个试验角色的模拟器实际材质画面通过检查；不把这些既有诊断写成“零警告”。

## 观感边界

这是星夜新增的克制上身动作，不是原作动捕。当前验证默认穿搭；没有做任意换装的全表面碰撞求解，也没有引入走跑、深蹲、接触脸部或全身重心移动。验收时可通过开关做相同角色的开/关比较，再决定保留或调整。原作眨眼、呼吸、风、表情、手势和口型不在这个开关的关闭范围内。
