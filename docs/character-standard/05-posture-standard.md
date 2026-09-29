# 持续姿势、对话配置与制作标准 · XCP / Character API 1.1

更新：2026-09-28。本文是新角色制作任务书的必读补充，适用于站立、坐下、蹲下、侧躺以及制作方新增的姿势。`schemaVersion` 和 `apiMajor` 仍为 1，新增能力为 `core.posture@1`，最低 `minApiMinor=1`。

## 1. 什么是姿势

姿势是用户可以保存、持续保持的身体状态，和“挥一次手”这样的有限时长动作分开。角色坐下后仍然可以聊天、使用口型、表情、目光和特效。结束一段语音、取消回复、打开面板、切换房间不会让角色自动站起。

当前已实现：

| 内容 | 本轮交付 |
|---|---|
| 小夏 | 站立、地面坐姿、蹲姿、侧躺；每种姿势 4 个参数 |
| 小乐，独立 GLB 样例 | 站立、坐姿、上身前倾参数；证明不同骨架共用协议 |
| Luma、初音旧包 | 原有站立/动作保持；明确返回未制作的姿势，不凭空变形 |
| 对话配置 | 本机受控语言解析 → 类型化姿势请求 → 引擎校验 → 回执后保存 |
| 精细设置 | 定制角色的“姿势”页，声明生成的按钮与滑杆；实时预览、取消、完成 |
| 自定义姿势 | 制作方可增加 ID、名称、clip、参数和动作映射；界面按目录生成 |
| 背景 | 与 XEP 独立组合，切换室内/室外不改变姿势；本轮支撑类型为地面 |

不把已有动作片段的最后一帧硬标成所有模型通用的自然姿势，也不允许对话直接写骨骼坐标。

## 2. 清单结构与命名

模型作者交付 GLB 内的动作资源和 `character.json` 声明。应用端只知道姿势/参数 ID 和可调范围，不知道骨骼路径。下面是结构示意；可实际导入的完整包见 `character-sdk/examples/sample-robot/`，不能把这个删节示意直接当成完整清单。

```json
{
  "compatibility": {
    "apiMajor": 1,
    "minApiMinor": 1,
    "required": ["core.animation@1", "core.gaze@1", "core.behavior@1", "core.posture@1"],
    "optional": []
  },
  "posture": {
    "bones": ["Rig/Pelvis", "Rig/Pelvis/Spine", "Rig/Pelvis/Spine/Head"],
    "poses": [
      {
        "id": "stand", "label": "站立", "symbol": "figure.stand",
        "clip": "Idle", "support": "floor", "gaze": "follow", "transition": 1.2,
        "parameters": [], "actions": [{"action": "Wave", "clip": "Wave"}]
      },
      {
        "id": "sit", "label": "坐下", "symbol": "figure.seated.side",
        "clip": "SitIdle", "support": "floor", "gaze": "follow", "transition": 1.3,
        "parameters": [
          {"id": "lean", "label": "上身前倾", "unit": "degrees", "min": -4, "max": 6, "initial": 0,
           "lowClip": "SitLeanBack", "highClip": "SitLeanForward"}
        ],
        "actions": [{"action": "No", "clip": "SitShakeHead"}]
      }
    ]
  }
}
```

- 必须有 `stand`，其 clip 必须为 `Idle`。标准姿势 ID：`stand`、`sit`、`crouch`、`lie`。`lie` 本轮样例为侧躺；其他躺法应使用独立稳定 ID，如 `lie-back`，不要修改已发布 ID 的含义。
- `label` 是用户可读名称，建议 2–8 个常用字；本机解析也能识别包声明的姿势名和参数名。`symbol` 使用系统可用符号，缺失效果应在原生界面验收。
- 每包最多 32 个姿势，每姿势最多 12 个参数、32 个专用动作；总姿势相关 clip 去重后最多 256。骨骼列表最多 128 条，必须唯一，不能是整个角色实例根的空路径。
- `bones` 列出所有参与持久姿势和参数插值的内部 Transform，包含需要移动的内部骨盆/根骨。不能把模型放置根、摄像机、灯光或背景节点放进来。
- `clip` 是稳定、闭合的循环姿势动作。首帧是参数参考姿态；可以有轻微呼吸。姿势 clip 与 `lowClip/highClip` 不需要放进普通 `actions`，不能因此额外出现一排动作按钮。
- `support` 本版只接受 `floor`。该姿势必须能在角色当前地面原点附近独立保持。坐椅/躺床/攀墙要等接触能力实现，当前不能用地面能力谎报。
- `transition` 为 0.6–3 秒。它控制到达该姿势的全身过渡时长，不是动画采样帧率。
- `gaze` 为 follow / soft / release。侧躺建议 soft；仍受原有头颈舒适角度与背向释放限制，不得为看镜头把头扭转 180°。

## 3. 高度定制的实际做法

不要暴露任意关节旋转给普通用户。制作方把经过检查的变化封装成命名参数，例如身体前倾、重心、双腿间距、手臂舒展、膝部收拢、头部姿态。不同模型可以提供不同参数，不强制使用相同人体比例。

每个参数提供：

| 字段 | 语义 |
|---|---|
| id | 永久稳定的参数 ID；供对话、资料保存和接口使用 |
| label | 用户可读名称，也可直接用于聊天配置 |
| unit | `degrees` 表示角度；`normalized` 表示 0–1 的作者定义变化 |
| min / max / initial | 可执行范围及参考值；`min < max`，initial 在范围内 |
| lowClip / highClip | 保持其他参数默认时，该参数最小/最大状态的静态完整姿势；运行时采首帧 |

小夏当前范围：上身前倾 −6°～10°、身体朝向 −15°～15°、双腿间距 0～100%、手臂舒展 0～100%。数值不是解剖极限，也不表示角色任意衣服都能承受同样范围。

执行顺序：动画评估 → 参数位置增量/四元数增量 → 姿势过渡 → 语音微动 → 有界视线 → 模型专用次级运动。参数数值通过阻尼跟随到目标，不逐帧跳变；姿势转换使用起止速度、加速度为零的五次曲线，骨骼旋转使用 Quaternion Slerp。身体变换不使用可能越过关节范围的弹性过冲；镜头仍使用现有弹性取景系统。

参数低/高样本相对于姿势 clip 的首帧计算差量，多个参数按 manifest 顺序组合。因此：

1. 默认样本、极值样本的参考原点、骨架、绑定缩放必须一致；不能不同参数各自移动整个角色实例。
2. 每个姿势 clip、参数样本、专用动作必须为 `bones` 中每条路径提供完整位置 XYZ 和四元数 XYZW 曲线，即使值不变。导入器会拦截缺轨，防止上一种姿势残留在下一种姿势上。
3. 姿势参数系统不插值骨骼缩放。避免姿势 clip 改变绑定缩放；身高和体形属于独立外观参数。
4. 制作时检查多参数组合，不能只检查每个滑杆单独拉动。关节增量组合并不等于通用碰撞求解器。
5. 坐/蹲/躺必须检查脚、臀、膝、肘、肩与地面的接触；手掌不能穿过躯干、腿和头发，脚不能悬空。首尾无问题不代表中间过渡无问题。
6. 头发和衣服的极值检查包括不同身高、体形、发型、袖口和裤装。宽松裙装如未制作坐姿修正，应缩窄范围或不声明该姿势。

编译器另外从实际变形网格的接触极值和姿势转换中选取最多 256 个蒙皮支撑采样点。运行时仅更新这些点，在必要时抬升内部根，防止转换时脚底进入地面；不逐帧 BakeMesh，不增加一套物理引擎。这是地面保护，不是脚部锁定、完整步态、家具 IK 或自碰撞。大幅体形 morph、不同服装及新增姿势仍需重新验收。

`minApiMinor=1` 和 `core.posture@1` 必须列为 required：旧运行时应拒绝不理解的新必需语义，不应把坐姿错播成站姿。没有 posture 段的旧包仍可在新 App 中使用。

## 4. 姿势上的动作

`poses[].actions` 将普通 `actions.id` 映射到当前姿势专用 clip。例如 Wave 在站立时是 StandingWave，在坐下时是 SittingWave。专用 clip 必须保持当前下肢和支撑关系，首尾回到该姿势。

当前只有一个身体动作槽，不是任意上/下半身蒙版混合。没有当前姿势映射时返回 `POSTURE_ACTION_UNAVAILABLE_OR_TRANSITIONING`，不自动站起，不播放普通站立动作。过渡进行中也暂不接受新的身体动作；表情、口型、视线、音频仍可继续。

动作结束和轮次取消返回**当前姿势的循环 clip**。改变姿势清除待执行身体/姿势 cue 和身体租约，接替正在进行的身体动作；已提交的持久姿势不会随着 turn.cancel 撤销。

行为规则也可使用 `channel: "posture"`、`target: "sit"`。这是能力允许的自动姿势意图。规则产生的临时自动姿势不写入用户资料；只有用户明确对话设置或点击完成才保存。未来服务可以基于用户授权、对话情景和环境能力发送相同接口，不需要改模型。

## 5. 对话接口和回执

外层继续使用 `character.signal`。新增信号：

```json
{
  "apiMajor": 1, "apiMinor": 1,
  "actorId": "real-woman", "sequence": 42, "eventId": "unique-event-id",
  "turnId": "", "eventName": "posture.set",
  "intensity": 1, "audioTime": 0, "level": 0, "visemes": [],
  "posture": {
    "id": "sit",
    "parameters": [{"id":"lean","value":6},{"id":"legRoom","value":0.35}]
  }
}
```

这是一次**完整目标设置**，不是部分增量补丁。未提供的参数回该姿势的 initial。原生端会先与保存的该姿势参数合并，再发送全部参数。接口层超范围、NaN/Infinity、重复/未知参数、未知姿势全部拒绝，保持原来的姿势；用户语言层可以把“前倾 90 度”限制到作者范围，并在回复中说明限制。

新增状态在桥事件的 `posture` 字段中：`revision`、`supported`、`id`、`support`、`status`、`transitioning`、`progress`、`parameters`。`parameters` 为已接纳目标值，`progress` 为骨骼姿势过渡进度；参数阻尼尚未结束时即使 progress=1，transitioning 仍为 true。`groundLift` 为轻量地面保护当前施加的抬升米数。正常使用只在状态变化/完成时回传，不传每帧骨骼。

- `characterReceipt`：已接纳/拒绝目标，**不代表视觉过渡已经结束**。
- `postureConfigured`：目标变化。
- `postureSettled`：骨骼过渡和参数跟随完成。
- 错误码：POSTURE_INVALID、POSTURE_UNSUPPORTED、POSTURE_UNAVAILABLE、POSTURE_SUPPORT_UNAVAILABLE、POSTURE_PARAMETER_INVALID、POSTURE_PARAMETER_UNKNOWN、POSTURE_PARAMETER_RANGE。
- 去重、序号、actorId、presentationId、turnId 沿用 Character API 1.0。

本机可试：

- “你坐下陪我聊吧”“蹲下吧”“侧躺休息一下”“站起来”。
- “上身前倾 6 度，把腿收一点”“向左转 10 度”“手臂舒展 70%”。
- “不要站起来”保持当前姿势；“我坐下了”不会被当作给角色的动作命令。
- 同一条消息要求多个不同姿势时先提示明确选择，不猜执行顺序。
- “在床上躺下”明确说明当前不支持家具自动贴合，不制造成功结果。

这仍是本地受控解析，不是任意自然语言运动生成大模型。新姿势名/参数名可由目录识别；复杂时序、任意物体位置、双人互动必须先有对应执行器和能力协商。

## 6. 用户资料、取景与场景

`CharacterStudio.posture` 为新增可选资料：`id` 加 `values[poseId][parameterId]`。每角色独立保存，各姿势单独保留调节值；旧档案没有该字段时默认站立，历史和记忆不变。外观“恢复推荐”和空间重置均不删除姿势设置；姿势页恢复推荐仅清当前姿势参数。

聊天配置收到引擎 accepted 回执后才保存和回复成功。停止文本输出不会撤销已经确认的用户设置。面板拖动只是预览，取消恢复打开面板时的设置，完成才保存。App 重启或重新进入角色时恢复保存目标。

非站姿使用自己的全身取景包围盒；编译器烘焙基础姿势、参数端点、专用动作范围，并提供余量，镜头平滑跟随新目标。不会把坐姿继续塞入站立脸部的取景中心。横屏中的宽低姿势会平滑构图到聊天区上方，避免侧躺的脸被聊天状态栏遮挡；完整包围盒继续参与边界求解。包围盒是取景保护，不是自动碰撞保证。

XEP 场景当前只提供参考身高、地面和角色原点周围净空。室内/室外场景都可与地面姿势组合；背景旋转不会强迫角色改变姿势。椅子、床、台阶、坡面、用户拖动家具的自动坐靠暂未实现。

未来接触能力应单独版本化：场景提供 surface ID、类型、局部坐标、法线、尺寸、承载范围、可达区域；角色提供接触点、支撑组合、骨架适配、IK/碰撞代理和可失败的过渡计划。现在不能在 optional 里随便写 `core.contacts@1` 就声称支持。旧包缺失时明确降级为已制作的地面姿势。

## 7. 交付与验收

必须交付完整姿势循环、低/高参数样本、姿势专用动作、完整 JSON、许可说明、可编辑源和可复现检查证据。精致真人角色目标应有站/坐/蹲/躺 4 类；不能承受某类的资产应明确列出缺失，不用扭曲骨架凑数。

验收至少覆盖：

1. 四类姿势正面/侧面/背面和实际聊天视角；地面接触、衣物、头发、手掌和眼睛。
2. 所有两两姿势切换，反向切换，转换中连续新请求；无瞬移/断肢/穿地/反向关节。
3. 参数最小、默认、最大和合理组合；换姿势再换回参数保留。
4. 每个专用动作首尾回正确姿势；缺失动作明确降级；中断不站起。
5. 说话、头部触摸、视线、表情、转身与各姿势叠加，头眼不突破舒适限制。
6. 面板预览/取消/保存、键盘、窗口大小、背景切换、重启恢复、旧资料迁移。
7. 完整 App 的真机 CPU/GPU/温度/帧时间采集。模拟器结果不等于 iPhone 120 FPS。

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r character-sdk/requirements.txt
.venv/bin/python character-sdk/tools/character_tool.py seal my-character
.venv/bin/python character-sdk/tools/character_tool.py validate my-character
.venv/bin/python character-sdk/tools/character_tool.py compare old/character.json my-character/character.json
.venv/bin/python character-sdk/tools/character_tool.py pack my-character my-character-1.1.0.xcp
.venv/bin/python -m unittest discover -s character-sdk/tools -p 'test_*.py' -v
```

`compare` 检查姿势删除、支撑语义变化、参数 ID/单位/范围/默认值变化、专用动作删除。新增必需能力也会被标记为需要升级审查。不能承诺任意未来骨架、布料或接触算法变化都无迁移成本。

实现依据：采用 Unity 的动画与采样机制、标准 glTF 动画资源及规范化四元数插值；本项目的持久姿势契约是建立在这些能力上的应用协议。[Unity Animation](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/animation)、[glTF 2.0 动画规范](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#animations)。
