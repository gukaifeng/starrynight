# 待机搭话与称呼 · 验证记录

日期 2026-10-01；App 0.71.0（98）。这是功能、数据流和抽样生成验证，不是新的真机帧率测试。

## 自动检查

- Python AI 全套：**187 passed，3 skipped**。日志 `.local/logs/idle-address-python-tests-final.log`。跳过项保持其原有条件，不计为通过。
- 新增待机检查覆盖 18 个角度轮换、只读检查不消费角度、账号/角色隔离、忙碌与明确安静要求、缓存修订与昵称失效、冷请求与预备请求末尾都包含选定意图、并发表演接收相同角度、准备不写历史、真正命中后记录候选原始角度并只补 1 组。
- iPhone 17 模拟器：`AddressPreferencesTests` 与 `CompanionExperienceUITests` 共 **2 项通过**，结果 `.local/checks/Idle-Address-v071.xcresult`。操作覆盖全局输入、返回保存、专属覆盖、清空继承、重启保留、全局清空；已查看截屏，中文标签与按钮未截断。
- 增补原生请求体断言后再次运行核心用例：**1 项通过**，`.local/checks/Idle-Address-v071-request-contract.xcresult`。确认多种对话触发都携带解析后的昵称及来源，兼容旧档案、跨账号隔离、游客只设昵称时的新账号迁移、云端写入失败回滚、空值持久化。
- 独立 Go 后端 `make test`、`make integration`、`make build` 均成功。集成测试实际连接 PostgreSQL/Redis，5 项通过，覆盖全局昵称保存、与其他设置合并、不串账号、清空后另一 API 实例读取。日志在 `backend/.local/logs/idle-address-{tests,integration,build}.log`。无需数据库结构迁移。

## 真实 AI 的少量抽样

使用 `scripts/live_idle_address_smoke.py --allow-paid` 做 3 个文本场景，随后针对偏差复测真冬 1 次，**总共 4 次 plan 调用，账本状态均 completed**；未调用 TTS、ASR、音色设计或批量预热。隔离测试 owner 和完整响应在本机 `.local/checks/idle-address/live-report*.json`，不提交真实网关状态、Key、音频或调用原始日志。

实际抽样：

- 琪宝关心当前活动：“你现在是正忙着，还是也有空发呆呀？”
- 青柠以英语关心已告知的忙碌，并使用指定昵称 River。
- 真冬第一次仍在继续讲旅舍名字，没有充分回应沉默。检查发现选定角度虽进入状态 JSON，最后事件只有泛化说明；将具体意图放到最后事件，并明确此次重心是用户。针对同一条件复测后成为：“不知道这些琐碎的事，你会不会觉得无聊？ 或者你想听听其他方面的？”

最后一例仍稍偏解释性，未来可进一步打磨角色口吻；本轮已实现期望的试探话题是否合适。四个样本不足以宣称所有角色每次都严格遵循，18 类规则轮换也不是对所有生成文本的人工验收。

新增缓存用例最初错误地向 Pydantic 已创建实例赋了原始 dict 消息，导致测试夹具类型错误；改为真实的已入库历史后通过。没有用放宽生产校验来掩盖测试失败。

## 部署与设备

- 本机 AI 服务通过 `scripts/install_character_ai_agent.py` 更新；只读检查确认运行中的完整待机规则和 provider 源码与工作区一致，昵称正确进入请求预览。`.local/checks/idle-address/runtime-check.json` 不包含凭证。
- iPhone Release 编译成功，`codesign --verify --deep --strict` 成功；安装回执 `.local/checks/idle-address/phone-install.json` 为成功，bundle ID 保持 `com.gukaifeng.xiaoban.dev`，不删除既有用户数据。
- 安装时 iPhone 可连接但锁定（`passcodeRequired=true`）。随后远程启动在 12 秒超时；安装成功与运行验证分开记录，不能声称此版已在真机完成交互验收。解锁后可手动打开星夜。
- 本轮 UI 和原生契约在 iPhone 17 模拟器验证；没有新增 iPad 验证或性能数值声明。

设计及入口见 [待机搭话与两级称呼](../../design/2026-10-01-idle-presence-addressing.md)。
