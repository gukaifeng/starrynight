# 星夜 · StarryNight

源码仓库：[gukaifeng/starrynight](https://github.com/gukaifeng/starrynight)。本库跟踪客户端源码、角色标准、工具与开发记录；受限角色资源、生成媒体、构建缓存和个人签名配置留在本机。新机器的资源恢复顺序与持续推送约定见 [Git 与资源恢复](docs/git-workflow.md)。仅克隆仓库不能直接构建包含受限 VRChat 角色的完整 App。

正式英文名 **StarryNight**，仓库和根目录统一为 `starrynight`。当前根目录 `/Users/gukaifeng/Documents/starrynight`，Xcode 真机入口为 `ios/StarryNight.xcworkspace`，模拟器入口为 `ios/StarryNight-Simulator.xcworkspace`，scheme 均为 `StarryNight`。命名约定与迁移记录见 [英文命名与目录](docs/project-naming.md)。

以精致 3D 角色为核心的 AI 陪伴产品。当前源码 **v0.103.0 / build 134**，名称保持「星夜」，默认月白深色主题，保留彩色星夜等可选主题，Logo 为极简月白星月矢量标志。原生 SwiftUI / UIKit + Unity as a Library，当前适配 **iPhone 17 与 iPad Pro 11 英寸 M4（2024）**。

v0.84 已切换至云端 HTTPS 入口 `https://39.105.116.74:8443`，iPhone 17 已安装并验证账户和 AI 认证链路。首次聊天需注册或登录正式账户；安装包不再包含旧 Mac AI 共享凭证。Mac 原服务及 AI 自动启动项已停用，旧运行数据按用户要求清理。见[服务端分离记录](docs/server-separation-2026-10-02.md)。

v0.67 为四位角色接入百炼生成的封面、头像与 2.5D 场景，并加入各自的前景粒子和唯一背景音乐。Fun-Music 邀测待开通，按用户选择先用匹配曲风的 CC0 音乐。输入支持键盘／按住说话、实时转写、上滑编辑与松手发送；智能回复预测独立使用 Qwen-Turbo，正式角色回答保持原模型。录音准备和消息写盘移出主线程，设备摇晃复用已有 AI 反应缓存。实施、测试与边界见[角色氛围与语音输入](docs/design/2026-09-30-character-atmosphere-and-voice.md)，私有资源恢复见[媒体制作](docs/character-media-authoring.md)。

v0.59.0 将加载中的消息也纳入自动跟随，并在实际内容布局完成后校准底部；保留手动翻阅历史。对话改用 Qwen-Plus-Character，真实 user／assistant 多轮历史与 AI 生成的本轮内容摘要共同推进聊天，所有场景仍调用真实 AI。重复候选在内部修订，低分语义相关不再反复作为拦截理由，不向用户抛出重复拦截提示。116 项服务测试、3 条模拟器实际流程通过，最终模型 8 轮真实会话验证全部返回有效新回复。详见[生成源头与滚动修复](docs/design/2026-09-30-source-dialogue-and-scroll.md)。

v0.58.0 将心声与真实动作说明提前编入有序回复，随语音／静音阅读进度穿插展开，兼容旧记录；引入历史原文、近似措辞与本地中文 BGE 召回，生成与拦截策略已由 v0.59 替代。轻晃门槛降为约 1 秒、两次小幅反向，冷却 20 秒。两平台构建、原生播放与手势回归完成，已安装 iPhone 0.58.0 / 84。详见[分段回复与去重记录](docs/design/2026-09-30-conversation-flow.md)。

v0.57.0 已接入全部角色表现的语义目录和多组时间轴，普通对话目标组合 4–8 项表情／动作；新分组通过 core.performance@2 扩展。静态外貌旁白隐藏，动作与心声用括号斜体；普通单指反复晃动会触发真实 AI 的撒娇／小生气和语音。已安装 iPhone 并读回 **0.57.0 / 83**；手机锁定阻止自动打开，模拟器验证通过。见[本轮实施与验证](docs/design/2026-09-30-expressive-conversation.md)。

服务端已独立迁入 [starrynight-server](https://github.com/gukaifeng/starrynight-server)，本机目录为 `../starrynight-server`。Go / PostgreSQL / Redis / Python AI 实现、部署、备份与维护工具均在新仓库维护；本仓库的旧服务端副本已移除。云端正式运行，本机旧服务已停止并清理；本仓库保留客户端、Unity、角色包标准和本地素材制作工具。

v0.52.0 核实琪宝、豆日向的原始 Prefab 与 FBX 均提供 15 个 VRChat 口型，当前 App 已保留 5 个原作元音形变，朗读由实际音频振幅驱动原作张嘴形变。修复连续语音分句和停止时的时间戳倒退，防止 Unity 拒绝后续口型；等待下一段音频时归零，并隔离过期的音频回调。真实 AVAudioEngine 播放回归通过，Unity 两角色实际网格检查共 23 项通过，未增加程序化说话头部动作。本轮没有付费 AI 调用，已安装 iPhone 17 并读回 **0.52.0 / 73**。详见[原作口型核查与同步修复](docs/verification/authored-lip-sync/README.md)。

v0.51.0 压缩「我的」页：头像、身份与设置同排，简介和四项关系入口组成紧凑信息区；作者主页移至「我的 → 角色」内，在同一窗口渐变进入。核查当前两份 VRChat 模型源包后，确认没有自带音频或音源组件，移除未接实际播放器的「角色音效」通道。声音面板只保留朗读、背景音乐与配乐选择，两项音量为零时正确显示静音，旧偏好兼容读取。三个针对性测试最终通过，已通过 Wi-Fi 安装 iPhone 17 并读回 **0.51.0 / 72**。详见[布局、音源审计与验证](docs/verification/compact-profile-audio/README.md)。

v0.50.0 将底部「首页」改名「对话」。角色左右旋转继续不限圈数，上下限制为 ±25°，旧存档中的倒置角度自动规范化。消息左滑可选「不显示」，保留记录与订阅，支持撤销和恢复。发现页改为角色商城结构：精选封面、紧凑双列目录、创作者作品、分类、搜索、筛选与排序；与消息页共用 44pt 搜索框，当前目录与发布可见性仍在本机实现。五项针对性模拟器测试最终通过，已通过 Wi-Fi 安装 iPhone 17 并读回 **0.50.0 / 71**。详见[角色商城、消息隐藏与旋转限制](docs/verification/market-and-messages/README.md)。

v0.49.0 将启动页退出条件改为原生首页就绪，不再等待 Unity 和角色首帧。先显示角色封面、身份、已有对话预览与可用菜单，角色准备好后平滑显示。iPhone 17 模拟器单次测量原生首页于场景连接后约 0.68 秒出现；这不代表 3D 已加载完成，也不包含系统启动阶段。三项启动流程测试通过，已安装 iPhone 17 并读回 0.49.0 / 70。见[启动优化与验证记录](docs/verification/native-first-startup/README.md)。

v0.48.0 移除测试对话库、固定问候/分支故事回复和内置离线推理引擎，接入真实百炼角色对话、实时识别及每角色独立原创音色。采用 Plan → 资源匹配 → Narration 的两阶段编排；只有台词与声音事件进入 TTS。API Key 仅保留后端，付费测试显式开启，缓存播放不重复计费。开发后端目前运行在这台 Mac，手机需要同一网络；独立云部署尚未进行。详见[真实 AI 实施与运维](docs/design/2026-09-30-real-character-ai.md)和[验收记录](docs/verification/real-character-ai/README.md)。

以下为此前版本的交付记录。

v0.47.0 增强两位角色的自然待机：只放大上半身呼吸（琪宝4倍、豆日向3倍），更明显的头发与衣物风动，单次眨眼放慢至0.455秒且保留原间隔。表现面板每组增加明确的默认入口，恢复表情保留姿势/穿搭，顶部可全部默认；穿搭默认遵循作者defaultOn。原作动画与源资源保持，适配独立声明。见[方案](docs/design/2026-09-30-visible-idle-and-defaults.md)及[本轮验收](docs/verification/idle-refinement/README.md)。

以下0.46及更早段落为历史交付记录。

v0.46.0 只打包琪宝、豆日向，新增自然眨眼、原作呼吸与头发/衣物微风。豆日向补回遗漏的Auto_Blink形变和自动控制，琪宝用原闭眼形变配本地节奏；静态站/坐等姿势仍有原作呼吸，表情和睡眠优先。使用可选core.autonomy@1，原作130项表现及用户会话数据保留。详见[设计](docs/design/2026-09-30-natural-idle.md)、[制作标准](docs/character-standard/07-natural-idle-standard.md)与[本轮验收](docs/verification/natural-idle/README.md)。

**0.46.0 / 67 已通过Wi-Fi安装iPhone17，设备版本读回一致。** 自动打开被手机锁定状态拒绝，用户解锁点星夜即可，不需重新安装。iPhone17模拟器的双角色自然待机/表情优先级完整流程通过，普通模式已启动；本轮未把模拟器60/120 Hz数值审查当作真机FPS实测。

以下保留历史版本的能力与交付记录；旧角色数量、入口位置、安装失败记录等仅描述对应版本，当前状态以上文最新版本记录为准。

0.42.0 / 63 已完成输入区域外点按收键盘保留草稿、集中声音控制、原作待机/口型及动作恢复；声音单击总静音、长按分项设置，音乐支持手机静音模式下播放。当时的松手自动复位查看规则已由 0.43 的草稿与显式保存取代。见[0.42验收](docs/verification/conversation-controls/README.md)。

v0.39.0 将两套 VRChat 角色的原作表现接入统一可选能力 `core.performance@1`：琪宝 82 项、豆日向 48 项，覆盖表情、姿态、手势、耳尾和主模型配件；在会话角色资料中打开「角色表现」，同一弹窗内操作，镜头保持不变。源动画由隔离 Unity 按 60 Hz 采样并转换，旧角色继续使用原有协议。见[实现与限制](docs/design/2026-09-29-vrchat-performances.md)、[角色表现制作标准](docs/character-standard/06-performance-standard.md)和[实际验证](docs/verification/vrchat-performance/README.md)。

角色现在按创建定义展示：外观、性格、声音、背景灯光与取景固定；只保留专属音乐、共同记忆和聊天资料，左上身份胶囊内的小图标控制静音。拖动/捏合不再改变取景，头部轻触仅在角色声明互动时响应；琪宝/豆日向不再触发后加摇头。聊天区域固定原设置的60%，全局默认15pt字号，在「我的 → 设置 → 聊天字号」修改。

12角色各有一张实际3D封面，发现页两列紧凑卡片、36pt搜索框；资料显示封面，作者作品经资料进入，不再单设作者分栏。每位内置角色各两首原创无损音乐，24首实际录音相互独立，角色/实例的选择和音量隔离。创建角色当前继承底座封面与音乐文件，但选项与偏好独立。见[固定角色方案](docs/design/2026-09-29-authored-characters-and-covers.md)、[音乐](docs/verification/character-music/README.md)和[0.37验证](docs/verification/authored-characters/README.md)。

**0.38.0 / 57 新增 VRChat 来源角色「琪宝 / Kipfel」「豆日向 / Mamehinata」**，发现页搜索名字即可进入。两套主 PC 模型转换为独立 XCP，包含九动作、15个会话形变、头部触碰、发耳尾动态和每角色两首配套音乐；未引入 VRC SDK。当前仅个人本地预览，公开集成分发需另核对作者授权。

0.38.0 的两平台编译与真机包验签通过；两条 iPhone17 模拟器测试通过（涵盖两位新角色及原初音回归），模拟器恢复普通启动。**本轮手机一次安装失败：iPhone 不可连接；手机上的旧版未被更新。** 工作区为 device / Release。导入与失败处理、实际截图、复跑哈希在 [本轮验收](docs/verification/vrchat-import/README.md)；后续 AI 直接使用 [VRChat 导入 skill](.agents/skills/vrchat-character-import/SKILL.md)。上一版0.37.0的7条流程与手机安装记录仍保留。

以下为既有能力与历史迭代记录，旧的角色内外观/取景/聊天显示编辑入口已由本版固定设定和全局字号规则替代。空白收键盘保留草稿、手机安全区避让头顶、六套动态配套背景继续保留，见[0.36设计](docs/design/2026-09-29-safe-portrait-and-living-scenes.md)及[当轮验证](docs/verification/immersive-scenes/README.md)。

面板内的作者、作品、关注者、定制、一起及长图等改为同一窗口中的渐变子页面，统一返回按钮位置并继承根面板背景，进入下一层不会叠加背景或改变角色取景。角色资料缩小头像与名字，订阅紧邻名字，定制放在简介下方左侧；关注作者只放作者主页。聊天资料进入长图后返回保留搜索和列表。见[设计](docs/design/2026-09-29-fade-subpages.md)及[实际页面与验证](docs/verification/fade-subpages/README.md)。

本版新增三款立绘方向的二次元角色「优可」「维拉」「安宁」，在发现页搜索名字即可进入。近景会话、九段动作、细微呼吸／眨眼、受限发梢微风、透明镜片与发丝反光均集成；角色包、取景、背景、音乐和语音选项独立。顶部身份胶囊增加内边距，保留 32pt 圆头像及原触控区域。优可为 CC-BY 4.0 素材；维拉／安宁仅用于当前个人原型预览，不可连同公开版本再分发，不提供外观改作。详见[立绘角色设计与来源](docs/design/2026-09-29-illustrated-portraits.md)。

v0.33 修复多角色公共摸头响应：透明聊天上沿让触摸穿透、单击独立于取景锁、头颈反应不再被整身动作抢占；验证包含7个角色实际偏转、70%聊天区、资料页关闭及会话恢复。小光／小诗重点重做Toon材质、原始法线与发丝反光，晴川同步升级；30秒自然待机、呼吸、非等间隔眨眼与旧动作共存，头像跟随包版本更新。见[当轮结果与截图](docs/verification/portrait-refinement/README.md)、[方案](docs/design/2026-09-29-head-touch-and-anime-refinement.md)。

会话顶部头像与名字收进轻透胶囊，保留播放语音时的头像波纹。「定制」缩小为资料简介中的轻量入口；从会话打开的资料页移除「进入会话」，点击空白处或返回即可继续原会话；发现／作者作品的资料仍保留聊天入口。见[本轮验证与截图](docs/verification/identity-capsule/README.md)。

新增「我的 → 设置 → 存储与缓存」：显示语音、角色头像、对话长图的实际缓存占用，可分别勾选清理并刷新。保留聊天、账号、订阅、角色定制和内置资源；语音与头像内存同步失效，之后正常重新生成。使用中／最近分享的长图单独显示保留大小，避免影响导出或分享；扫描与删除在后台执行，无缓存时禁用清理。见[方案与清理边界](docs/design/2026-09-29-storage-cache.md)、[验证与页面截图](docs/verification/storage-cache/README.md)。

角色关系调整为「订阅角色、关注作者」：两种关系独立，旧版关注的角色自动迁为订阅，聊天与定制资料保留，不自动关注作者。每个角色有作者资料与主页，可关注作者、查看其公开作品；创作者可编辑公开名字、简介和圆形头像。发现页分角色／作者搜索，支持已订阅及关注作者作品筛选；我的通过订阅、关注、角色、聊过四项数字进入各自列表。私有作品只对本人可用，撤回后其他身份保留失效订阅占位并可移除；内置角色整理者「星夜」与原模型素材署名单独显示。当前均为本机可用流程，没有收费订阅、网络粉丝或跨设备发布。[设计与迁移](docs/design/2026-09-29-authors-and-subscriptions.md)、[后端契约](docs/api/authors-subscriptions-v1.md)、[验证与截图](docs/verification/authors-subscriptions/README.md)。

新增「对话长图」：会话顶部头像／名字 → 角色资料 → 对话长图，也可从定制→聊天资料进入。按最近10条、30条、全部或搜索选择精确起止消息，冻结本次片段；月夜／暖笺两种样式搭配当前角色头像、名字、正文与轻量星夜签名，日期时间可选。生成1080px宽PNG、完整预览后用系统分享或保存到文件；超长内容自动连续分图，中文字、emoji、换行不省略。后台逐图渲染、可取消，只导出选中文字和角色形象，不附带账号、记忆、设定或语音。全部离线完成，开关页面不改变角色取景。[设计](docs/design/2026-09-29-conversation-long-image.md)、[原图与验收](docs/verification/conversation-export/README.md)。

新增「一起」：在会话里点击顶部角色头像／名字，打开资料卡后进入。提供按角色搭配的原创分支故事《雨夜来信》《放学后的天台》《星海来客》，选择写入原聊天并朗读，暂停／重启保留进度，结局进入时光手记；相处页可设用户称呼、自述、关系、回应偏好和暂时不想聊的关键词。共同记忆新增从明确用户自述提取的待确认建议，只有确认后才进入记忆；时光页可记录心情与小事。全部按账号＋角色隔离，兼容旧存档。发现页增加日常／校园／幻想题材筛选。

「一起→更多」提供实时语音、看图聊天、云端记忆和创作者社区的独立预览页，均明确未开通；当前不录音、不上传、不显示虚假联网结果。现有本机语音继续可用。分支剧情是本地编写内容，普通对话仍是本地规则；不把这些功能描述为已经接入在线大模型。调研来源、优先级与实施范围见[竞品调研与方案](docs/design/2026-09-29-companion-experiences.md)，未来服务接入见[API契约](docs/api/companion-experiences-v1.md)，验收见[本轮验证](docs/verification/companion-experiences/README.md)。

窗口与角色取景已分开：资料卡、定制子页、面板展开收起、返回、窗外／滑动关闭、键盘和聊天高度调整都保持当前角色的位置、大小和观察角度。外观页不再自动切换近景／全身，关闭页面也不再重新取景。用户主动调整取景、解锁拖动缩放和恢复推荐仍有效；实际旋转设备继续适配屏幕比例。见[固定取景方案](docs/design/2026-09-29-stable-panel-framing.md)与[验证记录](docs/verification/panel-camera-stability/README.md)。

本版新增三个随包集成的二次元3D角色：银发幻想风「小光」、长发校园风「小诗」、短发少年「晴川」。在发现页搜索名字，打开资料后进入会话。使用VRoid旧版CC0模型及Overte来源、Apache-2.0的九段会话动画，保留署名与固定下载哈希；独立绑定动作、外观、背景、音乐及声音节奏。聊天可要求“点点头”“摇摇头”“抬手”“想一想”“侧耳倾听一下”“轻声讲述”“放松一下”“认真回应”；触摸头部可摇头回应。支持眨眼、表情、口型、受限头发／裙摆摆动、发色和服装配色。新角色当前只提供站立会话，声音仍共用已有离线音色，不宣称任意姿态零穿模或实测稳定120FPS。见[角色方案与来源](docs/design/2026-09-29-anime-ensemble.md)、[验证与交付](docs/verification/anime-ensemble/README.md)。

首页是持续保留的角色对话：去掉顶部黑色渐变与头像加载页，首页隐藏返回与动作按钮，点击圆形头像与角色名字进入资料卡，再进入定制，人物改为更近的构图。切换消息、发现、我的等菜单只暂停渲染和声音，回来直接恢复原角色、草稿、聊天位置和取景。新用户的初音未来随包集成。进程启动显示独立的全屏品牌开场，边播边加载，开场结束仍未就绪时继续流光呼吸，完成后柔和淡出。App内更换角色保留带角色名字的细星轨入场动画；两种场景不叠加。模型、外观、背景、灯光、姿势与取景完成配置并连续渲染三帧稳定画面后再淡入；取消入场自动招手，首帧就是最终聊天取景。同一角色跨菜单仍直接恢复。

角色预测使用既有的一阶 Markov 思路，按账户的切换顺序、访问频率与对话历史选择空闲时准备的候选。当前七个角色已驻留，准备工作是隔离副本的材质/纹理/GPU 首次使用预热，不切换用户正在看的角色。低电量、后台或温度异常时不启动额外预热。

每次真正进入会话，角色会先发出一条主动问候并按角色设置朗读。区分首次使用、首次认识某个角色、App重启、返回已有会话、切回熟悉角色、从后台回来；重启问候参考本地时段，已有对话与较长离开也有对应措辞。账号和角色各自保存相遇记录，游客同样可用，问候不占五轮用户聊天额度。加载取消、重复挂载或已在首页时再点首页不重复发言；静音时保留文字，手动点气泡仍可播放。只联动现有口型、语音波纹和表情，不触发会拉远镜头的全身招手。见[主动问候方案](docs/design/2026-09-29-proactive-greetings.md)与[模拟器验证](docs/verification/proactive-greetings/README.md)。

输入框录音中的停止控件改为11pt红色方块与26pt圆形底，保留44pt点击范围，麦克风及输入框布局不变。本次构建与交付见[录音按钮小改记录](docs/verification/recording-control.json)。

AI 气泡使用一条连续轮廓，左上角抬起一个柔和的语音区域，内含播放/停止与 `8″`、`1′08″` 简写时长，无独立小气泡、音柱或长按菜单。正文顶部与底部均留12pt，缩小原有上方空隙，播放按钮保持44pt触碰高度。播放时局部微光呼吸；历史中的双下箭头缩至13pt，不透明度在34%～46%间轻缓变化，单程1.8秒、上下总位移1.5pt；移除旧有14pt向下偏移，与输入框留出空隙，保持44pt触碰范围且不挤动输入框。默认仍自动朗读，“点击角色头像/名字 → 资料卡 → 定制 → 角色静音”关闭自动朗读，手动播放某条不改静音偏好。语音继续完全离线，带按账号与角色隔离的有界缓存。时长统一显示简写数字，不加“约”；合成前临时估算，完整播放后保存实际音频时长。只有实际播放时创建微光动效，未播放、准备中和结束后均为静态。

发现采用更紧凑的双列卡片、角色搜索与筛选。卡片不显示订阅状态，也不直接跳转会话；先打开统一角色资料，资料内订阅、查看作者、进入会话或定制。发现页资料为不透明夜底，会话资料保留模型后方渐变。全App角色及账号头像统一圆形，播放语音时对话顶部头像出现两圈扩散波纹，停止后移除；减弱动态使用静态环。底栏首页、消息、发现、我的只显示文字，与中央加号垂直居中对齐。消息页搜索本地双方聊天文字，显示匹配片段并定位原消息；支持较早的已保存记录。我的顶部身份即账号/登录入口，无额外标题；“订阅／关注／角色／聊过”统计数字直接打开各自列表，设置包含主题、关于和体验身份切换。已有用户主动选择的主题保留，新用户默认月白，位于主题首位；底栏加号没有“创建”文字。

每个角色依然是独立集合：模型、动作、背景、声音和音乐一起声明允许范围，个人配置、记忆与对话按账号及实例隔离。聊天页不再显示语音状态行、陪伴状态块或游客剩余轮数；游客仍可聊五轮，新账号承接游客记录，老账号恢复自己的历史；取消全部角色订阅后保持空状态。当前为本机对话与发布模拟，无服务器或跨设备同步，声音仍为已有离线中文音色的节奏预设。

“我的”顶部身份进入的页面统一命名为“账户”。采用原生分组列表：圆形头像与身份、星夜号和本次登录方式、微信／邮箱／手机号，以及独立的退出登录行。绑定方式以只读信息呈现，保留简短测试说明；退出仍保留本机角色与聊天记录。见[账户布局与验证](docs/verification/account-layout/README.md)。

当前设计见 [角色资料与原生手势](docs/design/2026-09-29-character-identity.md)、[本轮验证](docs/verification/character-identity/README.md)。手势由iOS原生识别器接收，Unity执行头部命中、取景范围与弹性响应；避免透明界面依赖UnityView触摸转发，导出强制nativeGestureRevision 2。默认锁定取景但仍可点头互动；资料卡→定制关闭锁定后可拖动/缩放。原生遮层始终位于Unity上方，仅淡出其内容；3D窗口保持不透明，结束时不再更换窗口层级，避免加载动画末尾的跳变。上一版的一体语音气泡与头顶互动继续保留。轻触头部保留精确面部命中，并增加随动画更新的紧凑头顶范围，刘海与头顶也能触发摇头，锁定取景仍可互动。[Logo SVG](assets/brand/starry-mark.svg)、[深底图标 SVG](assets/brand/starry-app-icon.svg)均来自同一组原生矢量路径；App内PDF透明，桌面图标保持1024px无透明PNG。

当前 **星夜0.35.0 / 54** 已完成六条相关iPhone17模拟器UI流程、两平台原生编译及Device Release严格验签。包括作者编辑和跨身份订阅、资料各层返回对齐、全部定制子页及键盘保持取景、聊天资料与长图连续往返、生成分享、共同记忆与功能预览。手机一次安装成功并回读相同版本，一次自动启动成功。沿用10角色Unity导出，模拟器恢复普通启动，工作区device / Release。完整结果见[本轮记录](docs/verification/fade-subpages/README.md)。此前左上角小胶囊布局继续保留，见[0.34.1记录](docs/verification/compact-left-identity/README.md)。

下文为之前迭代的能力和验证记录，页面入口以本节及本版方案为准。

0.14.1 将“回到最近”改为半透明小箭头，手动滚到底部会自动隐藏并恢复跟随；角色加载保留首页主体，快速加载跳过提示，较慢时显示可取消的小卡片后柔和过渡。21 项状态检查、加载组件与 UI 测试源码类型检查通过；这些改动现已随 0.15.0 完成真机编译安装，模拟器专项验收仍待完成。见[修复与验证边界](docs/verification/chat-loading/README.md)。

聊天页「右上定制 → 聊天显示」可调整区域高度（35%～70%）和字号（14～24），返回或点击窗外保存。最早消息可继续下拉到清晰区域；所有自有弹窗统一左上返回与窗外关闭，见[显示与窗口验证](docs/verification/chat-display/README.md)。

聊天文字、气泡及消息操作现已整体渐隐，靠近角色的内容比区域背景更早消失；状态和工具入口靠近输入框，见[内容渐隐验证](docs/verification/content-fade/README.md)。

iPhone 与 iPad 现已支持左右横屏：宽窗口采用左侧角色、右侧半透明聊天，键盘和编辑侧栏与模型共同适配；旋转保留输入草稿、姿势、取景偏好及未保存预览。窄窗口保留底部渐变聊天，首页横向角色卡片与登录表单按窗口宽度调整。见[横屏设计](docs/design/2026-09-28-responsive-landscape.md)与[历史横屏验证](docs/verification/landscape/README.md)。

应用和模型现在通过 **XCP 1.1 角色包 / Character API 1.1** 分开开发。首页、动作按钮和外观参数由同源角色目录生成；对话发送语义事件，由各角色自己的规则驱动动作、表情、口型、视线与特效。新增独立 GLB 角色“小乐”用于验证完整导入通路。见[架构与制作文档入口](docs/character-standard/README.md)、[直接交给其他 AI 的任务书](docs/character-standard/03-ai-handoff.md)和[SDK](character-sdk/README.md)。当前是构建时导入，新包需重新编译 App；VRM、运行时下载和多层动作混合属于后续能力。

小夏现在支持持续站立、地面坐姿、蹲下和侧躺，每种姿势可独立调整上身前倾、身体朝向、双腿间距和手臂舒展。直接说“坐下陪我聊天”“上身前倾6度，把腿收一点”即可配置，亦可在“定制 → 姿势”精调。动作结束、切换背景和重启会保留姿势；独立 GLB 小乐提供同协议坐姿样例。见[姿势标准](docs/character-standard/05-posture-standard.md)、[本版验证](docs/verification/posture/README.md)和[可交给其他 AI 的 SDK 1.1](docs/character-standard/deliverables/Xiaoban-Character-SDK-1.1.zip)。当前是作者制作的姿势及受限参数，不是任意运动生成或家具自动贴合。

背景现已独立为 **XEP 1.0 场景包**。可选择客厅、影棚、静夜小屋、花园、海边露台和独立 GLB 小院；配色、装饰、环境方向与光影按角色/场景分别保存，切换场景有柔和过渡。见[场景制作规范与 AI 任务书](docs/environment-standard/01-production.md)、[场景 SDK](environment-sdk/README.md)和[验证记录](docs/verification/environment-platform/README.md)。当前是受限参数布置，家具自由摆放、天气和手机下载仍属于后续能力。

角色会在舒适范围内看向用户：眼睛较快跟随、头颈柔和转向，侧后方逐渐收回，保留摇头和鞠躬的动作表达。真人新增独立眼球骨骼，初音使用原眼骨，Luma整体转头。见[自然注视方案](docs/design/2026-09-28-natural-gaze.md)和[验证记录](docs/verification/gaze/README.md)。

取景与角色定制采用更舒缓、带轻微回弹的连续过渡；音乐、工具、设定、记忆、历史、账号及关于统一使用渐变透明弹层。见[本版设计](docs/design/2026-09-28-soft-panels.md)和[实际验证／录像](docs/verification/soft-panels/README.md)。

聊天区扩至约半屏，增加历史消息可见范围；底部背景使用长距离缓和渐变，消息上沿逐渐淡出，键盘与面板切换沿用连续动画。见[本版改动与验证](docs/verification/chat-fade/README.md)。

新增微信、邮箱、手机号登录界面，三种入口共用本地测试账号 `XB-000001`。默认资料和验证码已填好，直接点击登录；首页“我的账号”可查看关联方式并退出。记住登录状态，退出保留角色和聊天资料。当前不接微信授权或短信／邮件服务。见[账号方案](docs/design/2026-09-28-demo-account.md)和[实际验证](docs/verification/account/README.md)。

SwiftUI / UIKit 原生宿主与 Unity as a Library 组成的 Universal App。首页选择可定制成年写实女性 **小夏**、原创机器人 **Luma** 或 **初音未来 Append**，统一采用「对话近景／全身互动」取景，大小 90%–110%、左右朝向各 20°，角色和房间铺满聊天页，底部为半透明渐变聊天层；键盘只推高聊天层，保留角色构图。直接左右拖动转向、双指缩放，松手后按角色自动保存；“取景”面板可精细调整与恢复推荐。保留按钮动作和轻触头部摇头。模型、贴图、动画和真实渲染缩略图均内置，无需联网加载。

v0.7.2 将弹窗、键盘、编辑预览和前后台恢复的布局变化统一为连续取景：3D 始终全屏渲染，渐变聊天层随界面平滑过渡。见[界面动画方案](docs/design/2026-09-28-interface-motion.md)和[验证记录](docs/verification/interface-motion/README.md)。

直接手势见[交互方案](docs/design/2026-09-28-direct-character-gestures.md)及[验证记录](docs/verification/direct-gestures/README.md)。v0.6.1 的全屏构图与底部渐变见[沉浸聊天方案](docs/design/2026-09-27-immersive-chat.md)和[实际截图](docs/verification/immersive-chat/README.md)。

新增“定制”：小夏支持脸宽、下颌、眼型、唇形、鼻翼、体态、腰胯、身高，提供四种肤色、两种发型及发色、虹膜、服装配色。三种角色均可选择晴日客厅／柔光影棚／静夜，调整主光方位、高度、亮度、影子深浅；预览、保存、取消和重启恢复按角色独立处理。详见[写实角色与空间方案](docs/design/2026-09-27-real-character-studio.md)与[模拟器截图和验收记录](docs/verification/studio/README.md)。

初音采用 **Tda / monjo3456 v1.06** 模型的 Unity 适配，保留原作者及改作者规约，用于当前个人非商业测试。包含挥手、跳跃、跳舞、鞠躬、转身、致意、应援七种按钮动作，以及待机、眨眼和触头摇头。详见[实现、画质与验证报告](docs/miku-development.md)及[第三方声明](THIRD_PARTY_NOTICES.md)。

三种角色共用原生分辨率、4× MSAA、HDR / ACES、实时软阴影和棚拍灯光。查看器默认请求 **120 FPS**，支持 60／120 切换并显示实际采样帧率。目标值、动画资源的 frameRate 和设备实际输出是不同指标；真机实测数据及适用范围见上述报告。

v0.5.1 更名与新图标见[品牌更新记录](docs/verification/xiaoban/README.md)。v0.5 新界面与背景音乐见[设计方案](docs/design/2026-09-27-warm-companion-ui.md)和[验收记录](docs/verification/atmosphere/README.md)。v0.4 规则和验证材料见[对话取景验收](docs/verification/framing/README.md)。v0.3 验证材料见[本地伙伴验收](docs/verification/companion/README.md)。前一版品牌与动作修正的 iPhone／iPad 记录保留在[栩屿 0.2 验收记录](docs/xuyu-simulator-review.md)，不将历史结果混作新版数据。初版双角色已完成真机签名、安装和启动；用户反馈后已重做动作与头发避让，后续已将小伴0.5.1以独立App签名安装到iPhone并启动，详见[真机安装记录](docs/verification/xiaoban/device-installation.json)。历史首版数据不作为新版性能验收。

## 直接运行

运行模拟器时，先用 `python3 scripts/generate_host.py --platform simulator` 生成模拟器入口，再在 Xcode 打开 **ios/StarryNight-Simulator.xcworkspace**，选择 **StarryNight** scheme 和 **iPhone 17 模拟器**，点击 Run。真机固定使用 **ios/StarryNight.xcworkspace**；模拟器构建不会再覆盖真机工程和运行目标。必须从 workspace 的宿主 scheme 运行完整 App。这台机器已保留 Unity 模拟器导出和构建缓存，也可重新安装运行现有构建：

```bash
bash scripts/run_simulator.sh
```

运行优化编译的模拟器版本，可用 `bash scripts/run_simulator.sh --release`。如果该配置尚未构建，脚本会自动构建。修改源码后先运行 `bash scripts/build_host.sh --release`；默认无参数仍使用 Debug，方便 UI 自动化和调试。这里的 Release 是 Xcode 编译配置，Unity Simulator 导出仍保留 Development Player 能力，不等于真机发行包。

在「对话」页点击右上角调整位置图标，打开可穿透手势的说明面板：单指旋转，双指缩放及平移；左右不限圈数，上下限制为 ±25°，缩放和平移继续遵守当前设备的显示范围。保留每个账号、角色最后一次位置，点击「恢复默认」复位。角色资料由左上头像与名字胶囊进入，声音与角色表现使用页面上的独立小按钮。当前两位 VRChat 来源角色没有后加的点击头部摇头动作。最新旋转与迁移规则见[本轮说明](docs/verification/market-and-messages/README.md)。

只运行现有 App 不需要一直打开 Unity Hub、Unity Editor 或 Unity CLI。

## 修改后构建

只修改 Swift / Objective-C++ / 原生资源：

```bash
bash scripts/build_host.sh
bash scripts/run_simulator.sh
```

修改 Unity C#、模型、材质或场景生成逻辑：

```bash
python3 scripts/export_unity_ios.py --platform simulator
bash scripts/build_host.sh
bash scripts/run_simulator.sh
```

导出脚本通过 Unity CLI 优先连接现有 Editor，未打开时使用 batchmode。Editor 重载代码时会等待 Pipeline 恢复，不重复打开同一工程。构建逻辑在 `Assets/Editor/BuildIos.cs`：重建正式场景、检查模型与动作、导出 IL2CPP、将 Data 放入 UnityFramework 并生成框架标识。**需要保留的场景修改应写入 Setup()，不要只修改生成的 ViewerScene。**

## 自动化验证

```bash
bash scripts/test_simulator.sh
```

XCTest 操作真实 App：加载取消及重试、30 个前台计时 tick 的等待超时及恢复、首页和关于、真实手势、Luma 动作与初音七种按钮动作、头部 / 身体 / 空白点击区别、动作切换、20 次进出、后台恢复。同时验证 60／120 帧率切换及原生分辨率。随后 Python 对 Unity 回传的实际相机参数、动作和性能事件断言。性能数据为渲染循环墙钟间隔，并非真机显示呈现的证明。上述为测试入口覆盖范围，每轮实际执行项与结果以对应版本验收记录为准。

每轮日志、`.xcresult`、截图、事件证据分别保存在 `.local/logs/`、`.local/checks/`，保留历史。测试延迟注入只在 DEBUG 且显式传入 `--ui-testing` 时启用。Release 可显式传入 `--capture-performance` 做本地初音动作和帧率采集；普通启动不记录或上传遥测。

另外运行 `bash scripts/test_miku_layouts.sh` 验证初音头部正负例、受限取景、帧率切换，以及 iPad Pro 11 英寸 M4 的横竖屏。

动作需要拉远镜头时，采用带轻微回弹的平滑过渡，结束后柔和恢复原取景；快速切换动作保留镜头当前速度。取景参数依旧按角色保存，用户拖动／捏合使用更快的响应。实现与验证见[动作取景过渡](docs/design/2026-09-28-action-framing-motion.md)。

## 真实角色对话与语音

正式会话通过云端 `https://39.105.116.74:8443` 的账户与 AI 代理服务运行；服务端源码、百炼配置、付费验证和部署入口均在独立的 `../starrynight-server` 仓库。本客户端仓库只维护登录、会话、UI、Unity 表现、已打包的开场语音和本地语音缓存。App 不携带百炼 API Key，不需要 Mac 常驻网关。

首次进入已完成的 11 个聊天角色使用本地打包开场；其余回复通过云端生成。当前新增的 5 个 VRChat 角色是本地模型预览，使用作者提供的封面，不调用对话、图片或语音生成接口，也没有专属音乐。这一边界由角色集合的 `previewOnly` 字段与离线开场包校验实现，详见[第四批本地预览](docs/verification/vrchat-batch-import/preview-04.md)。

## 工程关系

| 路径 | 职责 |
|---|---|
| `unity/CharacterRuntime/` | Unity 源工程：URP、模型适配、动作、镜头和触摸交互 |
| `ios/StarryNight/` | 原生源码：首页、角色档案、对话／记忆、语音播放、生命周期和桥接 |
| `../starrynight-server/` | 独立仓库：账户 API、AI 网关、数据、部署与付费验证 |
| `config/PlatformConnection.json` | 无密钥的云端 HTTPS 默认入口；本机差异配置在 `.local/platform-client/` |
| `build/unity-simulator/` | Unity 生成的 ARM64 Simulator SDK Xcode 工程 |
| `build/unity-device/` | 独立 Device SDK 导出，不与模拟器框架混用 |
| `ios/StarryNight.xcodeproj` | 脚本生成的真机宿主和 UI 测试工程 |
| `ios/StarryNight.xcworkspace` | 真机 App 入口，依赖、链接并嵌入 Device UnityFramework |
| `ios/StarryNight-Simulator.xcodeproj` | 脚本生成的模拟器宿主和 UI 测试工程 |
| `ios/StarryNight-Simulator.xcworkspace` | 模拟器 App 入口，依赖 Simulator UnityFramework |

本仓库的业务源码分原生与 Unity 两套，服务端在独立仓库。Unity 导出的 Xcode 工程是可恢复产物。`scripts/generate_host.py` 生成 workspace 和跨工程依赖，不需要 CocoaPods / Carthage / XcodeGen。`--platform simulator` 与 `--platform device` 分别生成独立工程，两者共用原生源码且可同时保留，互不覆盖平台设置。

## 固定工具版本

Apple Silicon / ARM64，Unity **6000.3.25f1 LTS** + iOS Build Support，Xcode **26.4**，iOS SDK / Simulator **26.4**，URP **17.3.0**，glTFast **6.16.1**，Unity CLI **1.0.0-beta.8**，Pipeline **0.7.0-exp.1**。宿主与 Unity Simulator 架构一致。当前 Pipeline 已实际连接、查询场景、执行导出通过；不打入本轮非 Development Build 的 Unity 运行包。

## 从干净目录恢复依赖

1. 安装 Xcode 及适用 iOS SDK，完成 Xcode 初次启动配置，并在 Xcode → Settings → Components 安装 / 启用 iOS 平台。本机已补齐 iOS 26.4（23E244）arm64 组件。可用 `xcodebuild -downloadPlatform iOS -buildVersion 26.4 -architectureVariant arm64` 下载，再确认 Components 中 iOS 已启用。Metal 编译工具缺失时运行：

   ```bash
   xcodebuild -downloadComponent MetalToolchain
   ```

2. 安装 Unity Hub、**Unity 6000.3.25f1 Apple Silicon** 和 **iOS Build Support**，在 Hub 登录并激活适用许可证。如果使用官方 Unity CLI，可分两步安装：

   ```bash
   unity install 6000.3.25f1 -a arm64
   unity install-modules -e 6000.3.25f1 -m ios
   ```

   必须检查 iOS 模块实际安装完成；本次 CLI 组合安装仅完成编辑器，随后单独安装模块才齐备。

3. 在项目根目录执行：

   ```bash
   python3 scripts/prepare_packages.py
   bash scripts/check_unity_dependencies.sh
   ```

   准备脚本按 `docs/package-downloads.json` 下载固定版本到 `.local/dependencies/upm/`，校验官方 registry SHA-1、包名及版本，并记录 SHA-256。manifest 使用相对于 `Packages/` 的本地 tarball 路径，重新克隆后应先恢复这些文件。URP、Test Framework 等由固定版本编辑器提供。

4. 如需复查 Xcode / Unity 的完整编译组合，执行 `python3 scripts/check_ios_toolchain.py`。

当前 Luma 由 `StudioRobotBuilder.cs` 自动生成，无须下载模型或贴图。初音的 PMX、贴图与 ReadMe 随工作区保存于 `Assets/MikuCharacter/Source/`，`asset-lock.json` 固定来源提交及逐文件校验；`MikuCharacterBuilder.cs` 在 Editor 中生成适配资源。旧版 RobotExpressive 保留作历史资源，不进入当前场景；只有复查旧版本且其文件缺失时才需要：

```bash
python3 scripts/fetch_sample_asset.py --output unity/CharacterRuntime/Assets/ThirdParty/RobotExpressive
```

资源脚本拒绝覆盖已有资源。重新下载后须补做 Unity 导入检查，不能沿用旧验证结果。

## 后续真机测试

2026-09-26 已增加真机 Release 编译准备和个人测试安装入口；安装步骤与当前边界见[真机安装说明](docs/device-installation.md)。真机 / 模拟器导出和缓存分别保留，同一个 workspace 按平台切换。重新导出时：

```bash
python3 scripts/export_unity_ios.py --platform device
python3 scripts/generate_host.py --platform device
open ios/StarryNight.xcworkspace
```

将 `ios/Config/Local.example.xcconfig` 复制为 Git 忽略的 `Local.xcconfig`（已有文件则保留），配置 DEVELOPMENT_TEAM；可用 MODELSPACE_DEVICE_BUNDLE_IDENTIFIER 配置自己的真机 App ID。个人测试可使用免费 Apple Account / Personal Team。连接、信任设备并启用开发者模式后，确认设备 UDID：

```bash
xcrun devicectl list devices
bash scripts/run_device.sh DEVICE_UDID
```

未连接设备时可用 `bash scripts/build_device.sh --unsigned` 提前完成 Release 编译；该产物必须经过开发签名才能安装。也可在 Xcode 中选择 StarryNight、自己的 Team 和真实手机后 Run。切回模拟器时运行 `python3 scripts/generate_host.py --platform simulator`。

初版双角色已完成真机签名、安装、启动和短时性能采集，详见初音验证报告；该数据不能作为动作修正版的真机结果。长时温升、耗电及不同设备状态仍需单独验收。没有发布到 TestFlight / App Store。

## 维护文档

- [品牌与产品路线](docs/product-direction.md)：精致角色、个性设定、对话与语音的后续阶段。
- [开发记录](docs/development-notes.md)：关键决定、异常根因和修复。
- [模拟器验收](docs/simulator-acceptance.md)：最终结果、截图、录像和证据路径。
- [运行结构与桥接](docs/runtime-architecture.md)：源码入口、消息和生命周期。
- [最初 V1 方案](docs/design/2026-09-25-v1-development-plan.md)：保留设计背景，最新用户要求优先。
- [原始交接文档](ios_3d_mvp_technical_spec_v1_1.md)：保留前序 AI 原文。
