# 原作口型核查与同步修复

版本：**0.52.0 / build 73**。日期：2026-09-30。

## 来源与范围

按用户要求检查当前两位角色的原始资源，仅使用作者提供的口型，不新增嘴部造型或说话时的身体、头部动画。来源与转换检查遵循 [VRChat 导入技能](../../../.agents/skills/vrchat-character-import/SKILL.md)，Unity 数值检查使用 [Unity CLI 技能](../../../.agents/skills/unity-cli/SKILL.md)。

| 角色 | 原始文件 | 核查结果 |
| --- | --- | --- |
| 琪宝 / Kipfel 1.0.3 | `Kipfel.prefab`、`FBX/Kipfel.fbx` | Prefab 配置 `lipSync: 3`，指向嘴部网格；FBX 提供 15 个 `vrc.v.*` 口型 |
| 豆日向 / Mamehinata 1.53 | `Mamehinata_PC.prefab`、`PC/FBX/Mamehinata.fbx` | 同样配置原作口型及网格，提供 15 个 `vrc.v.*` 口型；Quest FBX 也有相同命名 |

两位均有 `sil`、`pp`、`ff`、`th`、`dd`、`kk`、`ch`、`ss`、`nn`、`rr`、`aa`、`e`、`ih`、`oh`、`ou`。这是模型自带的嘴部形变，不是附带的语音录音，也不是单独的说话动画片段。

当前转换资源已经保留 `aa/e/ih/oh/ou` 五个原作形变及对应映射。实际朗读采用 `speech.mode = amplitude`，由输出声音的强弱驱动 `vrc.v.aa`，绑定权重为 0.55；五个元音映射可以接受协议提供的 viseme 权重。目前语音服务没有提供逐音素对齐数据，因此**本版是声音驱动的嘴部开合，不宣称精准音素对口型，也不宣称 15 个口型都已参与实时播放**。

`proceduralHeadMotion` 保持 `false`。原 ZIP、Prefab、FBX、角色包、已有自然待机及动作数据均未修改。本次没有新增资源依赖，也没有调用付费语音生成接口。

## 发现的问题与处理

已有播放链路为 `AVAudioEngine → CloudSpeech.onFrame → speech.frame → CompanionAvatarDriver → 原作 BlendShape`。原生端以前在每个语音分句重新从零上报 `audioTime`，而 Unity 按整次发言拒绝倒退时间；结束时还发送 `(0, 0)`。后续分句或停止帧可能因 `STALE_AUDIO` 被拒绝。修复前的真实播放夹具捕获到 **2 次时间倒退**，新增回归断言确实失败。

修复措施：

- 每段音频记录固定的整句起始偏移，播放计时及口型帧都使用同一条时间轴；缓存重播使用相同流程。
- 分句播放排空后及时发送零幅度，等待下一段网络音频时嘴部自然闭合。
- 每段音频使用独立回调标识，丢弃结束后迟到的音频计量、定时器或缓冲区回调。
- 停播发送当前播放时间的零幅度帧，然后进入 idle；重新发言才重置时间轴。

口型幅度继续来自实际输出混音器，网络预先到达的音频数据不会提前驱动嘴部。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| iPhone 17 模拟器实际音频播放回归 | 1 项 XCTest 通过，7.214 秒；包括分块播放、两段音频、无文字声音段、缓存重播、取消及段间静音 |
| 最终原生播放轨迹 | 95 个状态/帧事件，80 个音频帧，时间倒退 0 次 |
| Unity 原作嘴部检查 | 23 项断言通过；两个角色均接受全部 80 个播放帧，各自 5 个原作元音映射有效 |
| 实际网格变化 | 琪宝最大顶点位移约 0.001452、豆日向约 0.003780，单位为模型网格局部坐标；由 BakeMesh 前后比较所得 |
| 停播恢复 | 两角色张嘴归一化权重降至约 `2.38e-14`，额外头部旋转为 0° |
| 原生构建 | Simulator Debug 与 iPhone Release 构建成功；真机 App 严格签名校验通过 |
| 手机交付 | 安装成功，设备读回「星夜」`0.52.0 / 73` |
| 付费调用 | 本轮前后计费账本一致，也与上一版交付后的账本一致；测试仅播放本地合成音频夹具 |

Unity 检查将真实 AVAudioEngine 输出轨迹送入场景中两位实际角色的临时副本，检查原作嘴部网格顶点确实变化，而非只验证配置存在。它属于 Editor 网格与协议验证，不是手机端逐帧视觉或 FPS 实测。手机本轮完成安装及版本读回，没有自动触发新的付费问候。

本轮仅修改原生播放器及测试；Unity 新增的是 Editor 验证脚本，现有 Player 代码与角色资产未变，因此复用有效的 Unity 导出，无需重新导出引擎。

## 复跑与证据

实际源审查保存在 `.local/checks/lipsync-v052/source-mouths.json`；源归档版本和哈希见 `assets/characters/vrchat-sources.lock.json`，原始资源解析见本机 `docs/verification/vrchat-import/source-audit.json`。

运行播放回归：

```bash
zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 \
  'RealAIConversationTests/testAudioThreadPlaybackAndCachedVocalBeat' LipSync-v052-Final
```

测试 App 在 Documents 写入 `speech-playback-review.json`。将它复制到 `.local/checks/lipsync-v052/playback-after.json` 后，使用 Unity CLI 运行真实网格检查：

```bash
/Users/gukaifeng/.unity/bin/unity run \
  /Users/gukaifeng/Documents/starrynight/unity/CharacterRuntime --timeout 300 -- \
  -buildTarget iOS -executeMethod CharacterSpeechReview.Run \
  -logFile /Users/gukaifeng/Documents/starrynight/.local/logs/lipsync-v052-unity-review.log
```

主要本地证据：

- `.local/checks/lipsync-v052/playback-before.json`：修复前轨迹，2 次倒退。
- `.local/checks/lipsync-v052/playback-after.json`、`unity-mouth-review.json`：修复后播放与真实网格结果。
- `.local/checks/LipSync-v052-Final.xcresult`：最终 XCTest 结果。
- `.local/logs/lipsync-v052-device-build.log`、`host-device-20260930-043942.log`：真机构建结果。
- `.local/checks/lipsync-v052/device-install.json`、`device-app.json`：安装与版本读回。
- `.local/checks/lipsync-v052/usage-before.json`、`usage-after.json`：付费调用计数未变。

上述原始证据和第三方模型资源只保留本机，公开 Git 仅提交实现、测试与本记录。
