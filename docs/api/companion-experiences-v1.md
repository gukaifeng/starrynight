# 星夜陪伴服务接入契约 v1（待实现）

此文档定义后续服务端与数据库接入边界。**本版未部署这些API、未连接云数据库、未实现实时通话或图片理解。** App里的“更多”显示对应预览与不可用状态，不进行网络请求。当前可运行部分继续使用`CompanionStore`的本机原子存档与`DialogueProviding`适配器。

## 通用约定

- 路径前缀`/v1`，HTTPS；会话身份从经验证的访问令牌解析，禁止信任客户端提交的accountID。角色实例必须验证所有者／可访问权限，公开作品不等于公开用户聊天或记忆。
- 请求携带`requestId`（UUID，幂等）、`characterInstanceId`、`conversationId`、`schemaVersion:1`。写入带`expectedRevision`，冲突返回409及服务器版本，不静默覆盖。
- `CompanionContextV1`已在App中实现：角色ID、姓名、背景、性格、语气、用户的相处偏好、最多30条已确认记忆、当前故事节点。待确认／已忽略的建议不进入上下文。传输前服务端再次执行授权及内容边界检查。
- 日期使用UTC ISO8601；资源ID稳定不复用。新增可选字段向后兼容；枚举采用开放字符串并约定未知值降级；改变语义则升级协议版本。无法承诺任意未来功能零兼容成本。
- 错误结构`{code,message,retryable,requestId}`；401登录、403无权、409版本冲突、413附件过大、429限流、503不可用。客户端保留草稿，取消不重复提交。

## 服务端能力

| 接口 | 请求核心字段 | 返回／事件 | 本版对应 |
| --- | --- | --- | --- |
| GET `/capabilities` | 平台、客户端协议版本 | 每个feature的`available/reason/minVersion`，无服务时fail-closed | 四种能力固定为尚未开通 |
| POST `/conversations/{id}/turns` | 输入、上下文、clientMessageId | SSE `reply.delta/reply.final/expression/speech.segment/turn.cancelled/error`；所有事件含turnId与递增sequence | `LocalDialogue`与现有语音／表情桥接 |
| POST `/voice/sessions` | role、conversation、voiceId、locale | 短期实时会话令牌、transport、过期时间、实际能力；不在App里内置密钥 | 实时语音预览 |
| POST `/voice/sessions/{id}/cancel` | turnId／取消原因 | 幂等取消，停止音频与口型 | 现有本地stop可复用 |
| POST `/attachments` | MIME、大小、hash、用途 | 有效期短的上传地址及attachmentId；上传成功才提交对话 | 看图聊天预览，尚无选择／上传 |
| DELETE `/attachments/{id}` | expectedRevision | 删除任务与状态 | 后续补全真实删除UI |
| GET/PUT `/characters/{id}/memories` | 已确认记忆、revision | 来源、确认时间、编辑时间、tombstone | 共同记忆与确认候选 |
| POST `/characters/{id}/memory-suggestions/{id}/review` | `accept/reject`、sourceMessageId | 幂等确认结果 | 本机reviewMemory |
| GET/PUT `/characters/{id}/experiences` | 相处设定、故事进度、手记、revision | 同步版本及冲突字段 | CharacterRecord.experiences |
| POST `/stories/{id}/choices` | templateRevision、expectedNodeId、choiceId | 新节点、完成状态、角色回复、一次性结局事件 | StoryEngine与chooseStory |
| GET `/creators/{id}`、GET `/works` | 题材、查询、cursor | 公开资料、可访问作品、真实统计 | 现有发现页与题材筛选 |
| POST `/works/{id}/publication` | 草稿版本、许可声明、可见性 | `draft/pending/approved/rejected`及原因 | 现有本机公开；社区预览 |
| GET/POST `/works/{id}/comments` | cursor／正文／replyTo | 审核状态与真实评论 | 创作者社区预览 |

实时语音必须先经用户操作开始，检查麦克风权限并清晰展示正在录音；离开／后台／挂断释放会话。取消旧turn之后，旧音频和动作不得继续进入角色。看图聊天先展示所选附件，用户点发送才上传；上传失败保留草稿。这里描述的是后续实现要求，不是本版已实现能力。

## 数据实体与隔离

建议关系数据实体：accounts、character_instances、conversations、messages、relationship_preferences、memories、memory_suggestions、story_runs、story_choices、moments、attachments、creator_profiles、works、publications、comments。

- 私有实体共同键：`owner_account_id + character_instance_id`；messages再加conversation_id。角色模板与用户实例分离，角色复制不能复制别人聊天。
- story_runs唯一键：owner＋instance＋story＋run_id；story_choices唯一键：run＋expected_node＋request_id。版本固定，不在服务端更新模板时强行替换进行中的节点。
- memories保留确认人、来源消息、修订和删除标记；故事消息明确storyId，禁止默认为真实用户事实。建议不等于长期记忆。
- moments只使用真实用户记录／结局事件，无随机好感值；删除与设备同步均遵守同一owner边界。
- public作品只发布模板／作者明确选定内容。不得把CompanionContextV1、用户昵称、自述、避开话题、私有记忆直接发给创作者或其他用户。
- 音色和模型附件仍遵守角色集合许可与允许列表。语音克隆、虚拟付费关系、抽卡和未经许可的IP资产不在本次范围。

## 分期与验收

1. 认证／数据库／幂等消息与流式对话，保证取消、重连、字幕／语音时序；测端到端首包与完成延迟。
2. 长期记忆候选提取、人工确认、来源追踪、可编辑删除；不同账号／角色隔离回归。
3. 实时语音和视觉附件服务，完成权限、打断、后台释放与删除闭环。
4. 云同步冲突处理及创作者发布、搜索、评论；真实状态接入后替换预览，不能只移除“尚未开通”标签。

上线前以真实端到端测试证明能力；当前本机规则回复和短篇分支不代表已经接入大模型或实现自由生成剧情。
