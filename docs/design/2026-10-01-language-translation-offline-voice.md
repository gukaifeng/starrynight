# App 语言、气泡翻译与离线语音（0.81.0 / 109）

## 用户行为

- 「我的 → 设置 → 语言」：默认跟随系统，可选简体中文、繁體中文、English。按系统首选语言判断；非中英文回退简体中文，繁体地区/脚本正确识别。选择属于本机 App，切换账户不会重置，重启保留。
- 界面使用 Xcode String Catalog，834 条界面/系统权限文案覆盖三种语言。角色名字、用户资料、聊天原文、原始素材署名和开发者检查中的实际提示词是内容，不做界面字符串替换。
- 所有 UIKit 承载的 SwiftUI 窗口使用同一个语言设置，包括主界面、Unity 上的聊天、胶囊、底栏和独立面板。只更新 locale，不用更换视图 ID 或重建会话来刷新语言。英文统计栏和订阅胶囊适应更长文字。
- AI 保留角色原来的说话语言。回复与界面语言不同时，在气泡右下角显示小翻译入口，可切回原文。简繁转换在设备上完成；跨语言翻译按需调用现有快速建议模型。没有点击时不产生翻译费用。
- 翻译按原来的段落顺序显示，保留台词、心理描写的斜体和颜色、动作描写。翻译不改原文、不改播放的语音、不作为新消息送回上下文。按消息原文指纹及目标语言保存，原文更新后旧译文自动失效。
- 删除确认使用 0.46 秒淡入/轻微上移，关闭同样平缓；减少动态效果时为 0.20 秒淡入。确认框显示期间保留滑开的红色删除/不显示按钮；取消后再收回条目。实际删除仍需明确点击「删除全部」。

## 翻译协议与隔离

原生入口在 `MessageTranslation.swift`；它将可见内容投影成 `{id, kind, text}` 列表。`AIReplyContent` 根据相同 ID 显示译文，先用原文决定内容可见性，再替换文字，避免英文译文长度增加后被原有心理描写过滤器误删。

新增 `POST /v1/conversations/{character}/messages/{message}/translation`，Go 代理对应 `/v1/ai/.../translation`。请求包括 `target_language`（zh-Hans、zh-Hant、en）和可见段落。服务端：

1. 根据安装/账户认证取得 owner，仅接受该 owner、该角色已存储的 assistant 消息。
2. 核对每段源文存在于原始消息，限制段落数与文本长度；不接受 arbitrary 源文或不支持的语言。
3. 让模型只翻译，保留 ID、kind、顺序、换行；严格验证输出结构。相同 owner/消息/语言并发请求合并等待；翻译并发池与聊天生成分开。
4. 保存源文指纹与结果，命中时不再调用模型。失败不改变原文，也不写入上下文或语音。
5. 生成结束再次确认消息存在。清空聊天或删除会话同时清除翻译，避免删除期间的晚到结果复活数据。

初次见面的内置问候可能尚在播放、后台还没登记；点击翻译时先执行无付费的幂等登记，再请求翻译。原生本地缓存仍按现有账户/角色记录隔离。

标准依据：[Apple SwiftUI 本地化](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization)、[LocalizedStringKey](https://developer.apple.com/documentation/swiftui/localizedstringkey)、[NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)。主线程保留有限的语言检测结果缓存，不在每一帧重新运行识别。

后续新增界面文案要同时补三种语言；动态 UI 标签使用 `LocalizedStringKey`，UIKit 使用 `L10n.text`。内容字段保持 verbatim。系统权限弹窗/桌面名称由 iOS 根据系统本地化选择，App 内语言开关不强行改变系统键盘或系统权限界面的语言。

## 语音缓存问题与处理

手机实际旧目录中发现 215 个文件，共 63.76 MiB，接近原来 64 MiB 的 LRU 上限。旧缓存还位于系统可清理的 Caches 目录，且完整音频要等实际播放结束才写盘，停止播放可能使已经下载的完整音频没有保存。这是不能离线重播的具体风险，不应将其统称为网络故障。

本次将语音移到 Application Support 的独立目录，排除系统备份，采用首次解锁后可读的文件保护。首次使用保留并迁移已有文件，容量增加到 512 MiB；仍按账户、角色、消息、音频片段分隔。设置页的缓存统计/清理同步使用新目录。只有完整音频写盘，写入发生在下载完成时，不再等播放器结束。重播先读本地，不先要求 AI 服务健康检查。

容量上限和用户主动清理仍然存在；旧版已经淘汰或未完整下载的音频无法凭空恢复，需要联网重播取得一次。完整保存的音频可在重启后离线播放。没有把语音或密钥提交到仓库。

## 网络检查与实际边界

服务部署到既有 per-user LaunchAgent 运行目录，保持原认证和历史。真机只读诊断得到：认证 status HTTP 200（185 ms），Bonjour health 200（16 ms），同一 LAN 地址 health 200（25 ms）。报告在 `.local/checks/phone-ai-connection-109.json`，不包含凭证。

另外进行了很小的真实付费验证：角色文字 1 次（3 字，884 ms）、TTS 1 次（0.88 秒音频，总计 522 ms）、两段短句翻译 1 次（572 ms）。翻译返回 dialogue/thought 对应的原 ID，结构一致。其余自动化使用离线 fixture 或假 provider，没有付费调用。

这证明检查时手机→Mac→百炼链路可用，不代表已部署独立公网后端。Mac 休眠、服务停止或手机不在可达网络时，新 AI 回复仍受影响。本次不引入临时公网隧道、不把百炼 Key 装入手机。开发版有 `--connection-check` 只读诊断入口，发行构建不包含该页面。

## 验证与遇到的问题

- iPhone 17 模拟器：语言回退/显式选择/偏好持久化/三套资源、真实设置面板即时切换及重启保留、气泡原文与简繁译文切换、心理/旁白格式通过。
- 删除确认 UI 测试：全条目左右拖动、保持滑开状态、取消后收起、不显示/撤销通过。自定义确认框的 `.isModal` 使辅助功能把它归为 Alert，测试应按稳定标识定位，不能假设它是普通 Other 元素。
- 真实 AVAudioEngine 测试：两段（含非语言声音）顺序播放、磁盘缓存重新创建实例后的离线重播、下载完整后停止播放仍留存音频、后台缓存通过。不是仅断言一个 Boolean，也不是声称真机帧率经过基准测试。
- AI 服务测试：193 passed，3 个需要可选语义模型缓存的测试 skipped；新翻译测试涵盖认证隔离、合并请求、译文结构、原文不变、删除清理、模型用途选择。
- Go：`make test`（race）、带专用 PostgreSQL/Redis 环境的 `make integration`、`make build`、`make openapi` 通过。第一次未载入测试环境时集成测试按设计拒绝无专用测试库的运行，随后读取现有 `.local/environment` 复测通过，没有用内存假库替代。
- `scripts/check_localization.py` 校验 834 条三语文案及插值占位符。加 `--stringsdata-dir` 可核对编译器提取的新 UI 文案。模拟器 Debug 和设备 Release 签名构建通过。
- 视觉检查修复英文统计栏单词拆行；个人昵称/简介保留原文是内容边界，不是对用户名做翻译。删除确认截图、英文页面截图、译文截图和完整 xcresult 都留在 `.local/checks/`，不公开受限角色图像。

主要证据：`LanguagesVoice-109.xcresult`（首次组合运行中的语言/真实音频用例通过，删除定位失败已修）、`LanguagesDelete-109.xcresult`（删除与翻译通过）、`LanguageShellFinal-109.xcresult`（真实设置页与重启通过）、`language-ai-suite.log`、`language-go-*.log`、`translation-live-smoke-result.json`。

最终设备 Release 通过严格签名校验，iPhone 17 安装后读回 **0.81.0（109）**，无诊断参数的正常启动成功。手机新持久目录实际读到 224 个语音文件、69,406,336 字节，旧缓存已经随启动迁移；本次没有清空用户记录。安装、启动及目录回执分别保存在 `.local/checks/language-install-final-109.json`、`language-launch-final-109.json`、`phone-persistent-speech-cache.json`。真机确认了安装、启动、连接及缓存落盘；跨实例离线播放由上述模拟器真实音频测试验证，没有把它写成真机断网测试。
