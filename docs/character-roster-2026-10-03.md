# 16 个角色名册、原名和初始站姿

按用户指定名单，App 从 40 个角色缩减到以下 16 个。默认角色为 Chiffon，
排序与用户名单相同，稳定角色 ID 保持不变。

| 原展示名 | 当前原名 | 状态 |
| --- | --- | --- |
| 戚风 | Chiffon | 保留完整对话、语音及现有配置 |
| Fiona | Fiona | 模型预览 |
| Hikarun | Hikarun | 模型预览 |
| 草莓 | Ichigo | 保留完整功能 |
| 小春 | Koharu | 模型预览 |
| 青柠 | Lime | 保留完整功能，原有英语对话保留 |
| 真冬 | Mafuyu | 保留完整功能 |
| 美云 | Meiyun | 模型预览 |
| 米露菲 | Milfy | 模型预览 |
| 真央 | Mao | 模型预览，修正初始站姿 |
| 瑞希 | Mizuki | 模型预览，修正初始站姿 |
| perula | Perula | 模型预览 |
| 小梅 | Plum | 保留完整功能 |
| Ramune | Ramune | 模型预览 |
| 信浓 | Shinano | 模型预览 |
| Sio | Sio | 模型预览 |

## 安装包和本机资源边界

`assets/characters/active-roster.json` 是打包权威名单。Unity 的 Resources
角色 Prefab 只保留这 16 个，运行场景仍只预载默认角色，其余按需加载。
被移除角色的 GLB、贴图、完整转换、源 ZIP 和非 Resources Prefab 留在 Mac。
本机仍有 47 套处理包，包括历史版本；没有删除源档案。

原始原画资产目录、旧 PCM 和旧配乐也保留在本机。构建器把当前名册需要的
图片复制到 `.local/active-character-resources/` 后才交给 asset compiler，
并只打包当前五个完整角色的 PCM 与配乐。原生目录、集合、商城元数据、
封面、角色资料、署名和背景配置同步筛选。六个退役完整角色的 Unity 背景
通过 AssetDatabase 移到 `Assets/ArchivedAtmospheres/`，恢复名册时可以原样移回。
该私有目录已加入忽略规则。

当前 Unity Data 从此前约 13 GiB 降至约 6.2 GiB，签名后的 iPhone App
约 6.4 GiB。这是本机文件占用，不能当作未来 OSS 压缩下载体积。

## 初始姿势修正

Mao 和 Mizuki 的原包有名为 `idle` 的 8 秒动画，但该动画在零时刻使骨盆
和双腿进入弯曲姿势。预览包现在用各自经原生 Unity 检查得到的
`host-standing.json` 替换展示 Idle 的骨骼采样；只作用于明确审查过的角色。
源包和原始动画采样不变，衣发物理及眨眼数据保留。两套私有预览包版本
升为 `3.2.1`，并重新 seal、Setup、校验和导出。

实际 Unity 骨骼审查在第 0、4 秒都确认头部高于骨盆、躯干接近竖直；
完整站姿渲染可见双脚落地。随后在 iPhone 模拟器运行真实 App，确认两个
角色正常打开、原名显示、朝向正常且仍是模型预览。没有新增对话入口。

Chiffon 成为默认角色后，旧导出校验误把合法的 AvatarControlDriver Animator
判为未适配自动动画。已修正为允许由该可信驱动拥有的 Animator，继续禁止
其他自动 Animator、Legacy Animation 和 autoplay；原作表情控制保留。

## AI 身份与旧录音

独立服务端仓库已更新五个已有角色的当前身份名和公开资料。身份归一化在
剧情覆盖之后执行；规划提示明确以 `character_profile.name` 为准，旧聊天
中的译名不能覆盖当前身份。缓存上下文包含完整 PROFILES，旧未播放候选
不再命中新身份的缓存键。账号、记忆、剧情和已有音色绑定不变。

Chiffon、Ichigo、Mafuyu、Plum 的 12 段已有开场录音仍会念旧中文名，因此
用原批准音色重录了相同台词，仅更正角色名。当前开场编号升为 v3，v2 与
更早音频保留用于历史回放；Lime 的原有英语 v2 不重录。预览角色没有新增
人设、AI、音色、开场或生成图片。

服务端源码提交为 `7182e70`，实际发布目录
`20261002T154835Z-7182e7011f59`。使用 active 升级工具完成 PG/SQLite 备份、
API/worker 升级和健康检查。已在云端核对五个身份名、公开资料名及 revision，
API readiness 返回 200。此任务没有调用对话模型做付费问答测试。

## 实际验证与安装

- 包 SDK 校验、真实 Unity Setup/Validate、默认动作及眨眼/物理自主性审查通过。
- device/simulator 两套真实导出通过，stamp 对应当前 16 个模型与 6 个场景。
- 独立 Swift 检查通过 148 项，包括精确名册、原名、旧保存名不能覆盖当前名、
  五个完整角色服务路由保留、11 个预览请求在构造网络请求前被阻止。
- 手机内实际核心检查通过 132 项，确认 16 个 ID、5 个完整角色、11 个预览。
  手机构建时的检查集比后续 Mac 检查少 16 项旧保存名断言；运行逻辑相同。
- 实际 device/simulator App 的 Assets.car、PCM、CAF 和资源目录检查通过；
  编译图片中没有名单外角色，开场与配乐只对应五个完整角色。
- 当前五套已有媒体的 15 张图片哈希、尺寸、归属与绑定通过，11 个预览继续
  使用原提供资源；未调用图片生成模型。
- 服务端 28 项身份、开场/删除、剧情、已准备回复交接和目标回归通过，假
  provider 不产生付费模型请求；78 段服务端当前/历史 PCM 校验通过。
- 模拟器真实 UI 测试 `SelectedRosterUITests/testSelectedNamesAndStandingPreviews()`
  实际执行 1 项并通过，分别打开并捕获 Mao、Mizuki 画面。首轮测试已打开
  Mao，但旧返回按钮在当前会话布局隐藏，测试失败；修正为独立启动每个
  角色后通过。没有为测试修改产品导航。
- iPhone 17 已安装签名版本 **0.93.0（124）**，安装、核心检查启动和最后正常
  启动均由 CoreDevice 回报 success；保留现有账号及聊天档案。

原生 Unity 渲染和模拟器画面不能代替真机完整对话的帧耗时测量，本次没有
给出 FPS 结论。私有日志、源包/站姿快照、PCM 回执、UI 截图与 xcresult 位于
`.local/roster-20261002/` 及独立服务端 `.local/`，不提交公开仓库。
