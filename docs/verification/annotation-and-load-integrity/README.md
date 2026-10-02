# 括号、朗读与角色加载完整性

日期：2026-10-03。范围：客户端、Unity 公共运行时；AI 服务端变更位于独立的 `starrynight-server` 仓库。

## 结论与边界

用户提供的「扶着额头，故作痛苦」案例已成为逐字回归输入。能够确定并修复导致括号拆散、动作描写进入朗读的代码路径。客户端兼容旧记录，不改变消息、分段索引或渐进显示时间；服务端修复已部署。

用户报告的偶发下半身、衣物缺失没有在本轮复现，不能据此声称找到了该次故障的唯一原因。本轮确认了资源加载与全局卸载之间缺少明确保护，以及蒙皮裁剪范围依赖导入原始值的风险，补上通用防护，并检查了全部 16 个角色资源及四个角色的实际切换显示。

## 括号与非发音内容

原台词字段允许「扶着额头」「故作痛苦」这类未覆盖的动作短语。随后 `reply_flow` 可以在括号内逗号处切分台词，插入另一个结构化表情；客户端逐个片段解析，丢失了原括号的跨片段状态。因此，后面的动作文字和孤立右括号可能被视为正常台词。TTS 的旧动作识别也没有过滤这些短语。

处理分为四层：

1. 服务端增加中英文动作和明确心声的识别，新台词拒绝嵌入动作描写或不配对的括号，走既有内部校正流程。动作、心理仍使用结构字段。
2. 台词分句保护完整括号范围，不在括号内部插入表情、心理片段；普通「维生素（B12）」「明天（如果有空）再聊」保留。
3. 客户端 `ReplyDisplayText.repaired` 在同一 beat 的台词片段间保留括号状态，插入的结构化旁白不改变该状态。旧嵌套括号、混用半角和全角括号、孤立闭括号动作续文转为配对的非发音显示。保留原片段数量、类型与 `at`，避免打乱语音驱动的渐进显示。
4. 旧回复重播进入 TTS 前过滤动作、心声和错误括号续文；仅疑似异常台词使用 `annotations-v3` 音频键。正常离线音频键不变。重置会话同时删除该会话的旧键和修复键，其他会话缓存保留。

服务端 `reply_flow.REVISION` 升为 5，让旧结构候选不再被新的固定场景直接领取。没有重新生成角色图片、音色或预置语音。

## 模型加载保护

`ViewerController` 的实际异步资源请求不会因 `StopCoroutine` 被取消。原实现停止加载协程后，仍可能进行另一轮请求或全局资源回收。本轮不再以停止协程冒充取消请求；使用选择序号丢弃旧结果，等待在途加载完成后再回收资源。

- 角色加载与预热都计入在途计数；`finally` 释放计数。资源卸载等待所有在途请求完成，新加载等待已开始的全局卸载完成。
- 同一个下载角色的 AssetBundle 加载串行协调，避免重复打开同一包；卸载只处理已经不被角色缓存引用的包。
- 在角色进入缓存并通知原生页面可以显示之前，检查全部蒙皮网格、材质槽和 shader。缺失资源输出 `CHARACTER_LOAD_INVALID` 及具体网格错误，显示失败信息，避免让不完整实例进入正常会话。
- 每个蒙皮的 `localBounds` 合并角色整体静态包围盒和余量，减少导入时旧姿势、旧坐标范围引起局部误裁剪的风险。只在角色绑定时处理，不启用所有网格的每帧 `BakeMesh` 或 `updateWhenOffscreen`。角色取景仍使用原始取景范围。
- 原始网格、衣物开关、Renderer.enabled 和 GameObject.activeSelf 保持原值。不能为“完整”而把模型原本隐藏的衣物、身体全部打开。

Unity 官方说明，`Resources.UnloadUnusedAssets` 的检查不包含脚本执行栈，而蒙皮网格是否可见受包围盒影响，参考 [资源卸载说明](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/resources/unloadunusedassets) 和 [Skinned Mesh Renderer](https://docs.unity.com/en-us/engine/6000.0/manual/assets-and-media/asset-types/mesh/components-reference/class-skinned-mesh-renderer)。这些机制支持本轮防护选择，并不能证明用户那次偶发故障正是由其中某一种机制引起。

## 已执行验证

| 验证 | 真实结果 | 能证明的范围 |
| --- | --- | --- |
| 服务端完整 Python 测试 | 284 passed、4 skipped | 生成校验、原文过滤、分句边界、缓存键等既有与新增逻辑 |
| 服务端 Go race 测试、构建及独立 PostgreSQL/Redis 集成 | 通过 | 服务端本轮修改兼容现有 API、管理员及持久化逻辑 |
| 部署后新增回归 | 云端 10 passed | 运行中的发布源码包含这次文本和语音输入修复 |
| 原生 UI：结构化翻译/括号、渐进显示、真实 PCM 缓存重播 | 3 tests、0 failures，41.759 秒 | 使用生产 Swift 代码，不调用付费 AI；该组本身不包含 Unity 渲染 |
| 最终原生括号/缓存清理回归 | 1 test、0 failures，20.317 秒 | 同一会话的旧/新音频都删除，其他会话的缓存保留，正常 key 兼容 |
| Unity Editor 全名册检查 | 16 角色、294 蒙皮通过 | 网格材质完整、可见性状态保留；注入缺失网格时正确拒绝 |
| 实际 Unity iPhone 17 模拟器切换 | 1 test 通过，121.905 秒 | 按戚风→青柠→草莓→小猫→戚风→青柠顺序，检查模型 ID、待机状态及无加载错误，跨过两角色缓存容量 |
| 切换截图审查 | 6 张实际渲染截图检查通过 | 本轮画面未见身体或衣物局部消失，包含返回已淘汰缓存的角色 |
| Unity iOS simulator/device 导出 | 通过 | 本轮公共运行时已进入导出产物，目录与角色隔离检查通过 |
| 真机 Release 编译与签名检查 | 通过 | 最终生产 Swift 与 Unity 公共运行时可以完成签名构建，`codesign --verify --deep --strict` 通过 |

完整性检查里的 `sourceOutsideActor` 表示某个原局部包围盒不包含角色整体中心。身体不同部位的包围盒本就可能不包含整体中心，不能把该计数解释为同等数量的损坏网格。这里只验证防护后的包围盒覆盖，不伪造原资源故障证据。

测试录屏/截图、xcresult、原始模型与转换资产只留在 `.local/` 或原约定忽略目录，不提交公开仓库。这次没有调用百炼付费模型，没有真机 GPU 帧率或全部动作组合的结论。

## 遇到的问题与处理

- Unity 导出时发现图片背景绑定发生在角色选择之前，传入空 role 的字典查询抛异常。`CharacterImageBackdrop` 增加空角色保护后，两平台导出通过。这是本轮发现的构建初始化问题，不将其等同于用户报告的局部模型缺失。
- macOS 直接执行独立 Swift 回归二进制被系统终止，未产生有效结果。将断言加入现有生产代码原生 UI fixture，在模拟器实际执行后通过；不把被终止的试验算作通过。
- 服务端旧本机测试数据库的历史迁移状态与 sequence 不一致，本轮没有修改历史数据库或迁移源码。使用独立新建测试数据库执行集成测试后通过，临时本机开发服务已停止。

服务端源代码发布：`7573449`，云端 release `20261002T214932Z-757344956637`。公网 API ready 返回 200，管理会话匿名请求返回 401。详细服务端记录见 `../starrynight-server/docs/annotation-integrity-2026-10-03.md`。

## 回归入口与私有证据

- Editor 全名册：`CharacterLoadIntegrityReview.Check`，输出 `.local/checks/character-load-integrity.json`。
- 真实 Unity：`CharacterLoadCyclesTests/testCharacterEvictionAndReturnKeepsIdleReady()`，结果 `.local/checks/Character-Load-Cycles.xcresult`，6 张图片在 `.local/checks/character-load-cycle-all-images/`。
- 原生显示/缓存：`AppLanguageTests/testLanguageSwitchAndOfflineStructuredTranslation()`、`ReplyFlowTests/testAsidesArriveBetweenLinesWhileVoiceIsPlaying()`、`RealAIConversationTests/testAudioThreadPlaybackAndCachedVocalBeat()`；最终缓存清理结果 `.local/checks/Annotation-Cache-final.xcresult`。
- 云端文本/TTS 输入：`services/character_ai/tests/test_annotation_integrity.py`。样例作为确定性输入，没有依赖 AI 再次随机生成同一错误。

## 设备安装与同步

最终 Release 已安装到已配对的 iPhone 17，`devicectl` 返回 App installed，bundle ID 为 `com.gukaifeng.xiaoban.dev`。这是现有星夜的更新，没有卸载应用或清空真实账户、消息与模型下载数据。安装日志和 JSON 在 `.local/logs/annotation-device-install.log`、`.local/checks/annotation-device-install.json`。

随后尝试远程启动，iOS 明确返回 `Locked`，因此没有完成这次真机启动/画面检查，也没有把模拟器结果当作真机结果。用户解锁后可直接打开更新后的星夜，无需再次安装。

服务端代码及发布记录已推送至独立仓库 main（源码 `7573449`，发布记录 `002b0e4`）。客户端将本轮源码、测试及本记录一并提交并推送；导出产物、私有截图、模型资源、签名及缓存不公开提交。
