# 初音未来 Append：实现、画质与验证

2026-09-27 更新。第二角色初版已安装到用户的 iPhone 17，用户确认可运行并反馈动作僵硬、穿模。随后重做动作和头发避让，并将 App 更名为“栩屿”。按用户最新要求，修正版本轮在模拟器验证，尚未更新真机；原有 Luma 保留。当前工作区已恢复完整执行权限，早期受限会话的源码检查状态已被本次实际构建、渲染和运行证据替代。

## 可见功能与画质

首页两张角色卡片。初音提供 **挥手、跳跃、跳舞、鞠躬、转身、致意、应援** 七个按钮动作；轻点头部摇头，动作后返回待机，包含眨眼、微笑及双马尾摆动。查看器保留旋转、缩放、复位和 60／120 FPS 切换；手机动作栏可横滑，iPad 支持横竖屏。

最终模型为 **Tda 式初音未来 Append / monjo3456 v1.06** 的适配，外观是 Append 服装。原始 PMX、贴图、作者日文规约及参考译文保存在 `Assets/MikuCharacter/Source/`；来源固定为公开仓库 `hecomi/StereoAR-for-Unity` 的提交 `6b64a9547b13ccc5052430177ee46c8d24722752`，下载时验证 Git blob，SHA-256 记录于 `asset-lock.json`。App 关于页内置完整署名与规约。模型数据不受源仓库其他代码许可证覆盖；本次用于个人非商业测试，没有发布或上传。

前期程序化试制模型在真实渲染审查中未达到外观要求，因此没有作为最终初音交付。当前可见模型为 **24,774 顶点、32,918 三角面、2 个蒙皮渲染器、15 个材质槽**，保留 208 个骨骼层级。最高实际源贴图为衣服的 **2048×2048**；面部、头发和另一张衣物贴图为 1024×1024，补充纹理为 512×512。导入上限 4096 不表示源文件是 4K，也没有放大源贴图冒充新增细节。

贴图启用 mipmap、三线性过滤、8× 各向异性与 iOS ASTC 4×4。衣物和头发使用 URP 光照材质，面部采用柔和动漫明暗着色，保留眼睛、发丝和服装图案。共用原生分辨率、4× MSAA、HDR / ACES、4096 主光阴影图和实时软阴影，未通过降低 renderScale 或关闭阴影换取 FPS 数字。

真实画面见 [面部近景](verification/miku/face-editor.png)、[挥手姿态](verification/miku/wave-editor.png)和[鞠躬姿态](verification/miku/bow-editor.png)。这些是 Unity 实际渲染；Editor 静帧用于检查外观，不构成设备性能证明。

## 实现与取舍

- `PmxModelData.cs` 只在 Editor 读取网格、UV、法线、权重、骨骼和表情，`MikuCharacterBuilder.cs` 生成 Unity Mesh / Material / AnimationClip / Prefab。保留三种实际使用的表情，省略默认隐藏的猫耳、眼镜和旧阴影片。
- 4,842 个 SDEF 顶点转换成 Unity 线性双骨骼蒙皮。没有实现完整 MMD IK、物理或原动作播放兼容；七个按钮动作由本项目编写（用户反馈后已重做为手脚协同轨迹），未包含第三方歌曲、舞蹈文件或音频。头发使用动画目标和 14 段轻量弹簧链，胶囊约束避让身体、手臂及大腿；这不是完整 MMD 刚体物理。
- `MikuMotionBuilder.cs` 在 Editor 中使用真实骨架的双骨骼 IK 烘焙手、肘和脚的协同轨迹。动作有准备、保持和回收，跳跃含下蹲与落地缓冲，身体重心变化时脚保持落点，双手不再收拢交叠。使用四元数曲线、平滑起落和 0.24 秒动作渐变；常量通道只保留两个关键帧。Clip frameRate 标记 120，该字段不能证明屏幕输出 120 FPS。
- `selectModel / modelSelected` 带 presentationId、requestId、modelId；确认选定角色后才显示 Unity 窗口。切换时清空旧动作完成协程、头部缓存和手势，重算镜头并预热统计；旧角色回传事件不会污染新角色标题或 FPS。
- 轻点时对当前头部蒙皮执行 BakeMesh，再做射线与真实三角面求交；不在每帧烘焙。背景、身体点击和拖动手势不触发摇头。
- 动作剔除边界与镜头适配边界分开。初音竖屏取景系数 0.70，随画幅变宽回到 1；Luma 系数为 1。修复从机器人取景直接复用导致初音在手机上过小的问题。
- Unity 导出内容版本为 2，构建前验证两个角色及缩略图，拒绝旧 Luma-only 导出。真机和模拟器各自导出，生成器保持宿主及框架平台一致。

## 可重复验证入口

```bash
python3 scripts/check_character_sources.py
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/test_simulator.sh
bash scripts/test_miku_layouts.sh
python3 scripts/export_unity_ios.py --platform device
bash scripts/run_device.sh DEVICE_UDID
```

`test_simulator.sh` 覆盖加载取消、超时恢复、Luma 全部交互、22 次展示与跨角色切换，并对实际引擎事件断言。`test_miku_layouts.sh` 补测初音头部命中/负例、缩放/复位、帧率切换，以及 iPad Pro 11 英寸 M4 横竖屏布局。XCTest 的短暂“正在跳跃”状态容易在主机负载高时被快照错过；七动作开始、完成的最终判断使用真实桥接事件，不能仅凭恢复待机标题认定成功。

物理设备性能采集通过显式启动参数 `--capture-performance`：进入初音，120 与 60 模式分别轮播七个动作，再恢复 120。采样保存在本 App 的 Documents/performance-capture.jsonl，仅本地读取；普通启动不记录、不上传。采集期间临时防止自动锁屏，结束、退出或切后台恢复。`--preview-miku` 只直接打开角色，不自动播放测试序列。

帧率是 Unity player-loop 的墙钟间隔，2 秒一窗；配置、前后台切换后预热 1 秒，除此以外不删除慢帧。它不是 GPU 时长或物理显示呈现的逐帧跟踪。模拟器只有 60 Hz，不能验证手机 120 Hz。短时真机结果也不能保证低电量、温升、系统调度或长期运行中的每一帧。

详细验收结果及证据继续记录在本文件和 `verification/miku/`，关键决策、失败根因与修复见 [开发记录](development-notes.md)。


## 真机反馈后的动作修正

用户在真机指出初版僵硬和局部穿模，已据此重做动作，未把自动功能测试通过当作动作观感达标。首批真机旧动作数据单独保存在 `initial-device-performance.json`；其中初音 120 目标的 62.018 秒采样平均 119.97 FPS，最慢 15.592 ms，不能直接作为新动作 / 头发避让版本的结果。

新动作按 120 Hz 共采样 **4,173 个姿态**，覆盖待机、七个按钮动作和摇头。手腕最小间距 1.280 单位，前臂与身体保护包络最小余量 0.163 单位，未进入头部保护包络；非转身动作脚踝相对落点最大高度误差约 0.000036 单位。每个动作在 20% / 50% / 80% 时间点渲染三视角，共 81 张检查图。见 [检查数据](verification/miku/motion-validation.json)。这是针对已知问题的姿态与包络验证，不能证明所有材质表面和饰带在任意连续切换中永不穿插。
