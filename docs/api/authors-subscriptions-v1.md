# 后端接入契约：作者与角色订阅 v1

当前实现是`CharacterLibrary`本机仓库。以下接口为后续服务契约，尚未部署，不把本机公开或本机数量表述成真实网络结果。

## 公开资源与私有关系

- `Author { id, name, bio, avatar, revision }`：公开ID不可由手机号／邮箱／登录ID拼接；头像后续可扩展为受控图片资源，保留现有样式fallback。内置作者`starry-studio`为预置整理者，素材来源另存`credits`。
- `CharacterListing { id, authorID, display, collectionID, visibility, updatedAt, revision, sourceCredits }`：归属由服务端认证身份决定，发布请求不能任意指定别人的authorID。客户端对角色的个性化名称、外观和聊天不反写公共作品。
- `CharacterSubscription { characterID, createdAt }`与`AuthorFollow { authorID, createdAt }`是两张独立、以当前身份为作用域的关系；均不表示付费权益。
- 本地ownerID→authorID映射、账户认证、手机／邮箱、聊天和记忆不在公共API响应中。作者页只返回公开作品；我的草稿需独立授权查询。

## 端点

| 方法／端点 | 行为 |
|---|---|
| GET /v1/authors?query=&cursor= | 作者发现与分页搜索 |
| GET /v1/authors/{id} | 公共资料与服务端统计；不可用返回明确状态 |
| GET /v1/authors/{id}/characters?cursor= | 仅公开作品，按updatedAt和id稳定排序 |
| GET /v1/authors/{id}/followers?cursor= | 仅经产品隐私设置允许公开的作者身份，不返回登录账户标识 |
| PATCH /v1/me/author | 仅修改本人资料；带If-Match或expectedRevision，版本冲突返回409 |
| GET /v1/me/character-subscriptions?cursor= | 包括失效项状态，供取消；不可借失效项读取已私有的作品内容 |
| PUT /v1/me/character-subscriptions/{id} | 幂等订阅，必须可访问；不自动关注作者 |
| DELETE /v1/me/character-subscriptions/{id} | 幂等取消，包括失效项；不删除聊天与作者关系 |
| GET /v1/me/author-follows?cursor= | 当前身份关注的作者 |
| PUT /v1/me/author-follows/{id} | 幂等关注；拒绝关注自己及不存在的作者，不自动订阅作品 |
| DELETE /v1/me/author-follows/{id} | 幂等取消，保留角色订阅 |
| GET /v1/me/following-characters?cursor= | 关注作者的公开作品；按更新时间稳定分页，客户端按角色id去重 |
| PUT /v1/me/characters/{id}/publication | 仅作者本人发布／撤回／更新，带expectedRevision，不上传聊天、记忆与私有相处档案 |

所有`/me`资源从认证会话推导身份，忽略客户端传入的ownerID。写操作返回确认后的资源、关系状态及revision，客户端只在成功后更新。离线队列若后续增加，需按资源保留最后意图，不因重复PUT增加计数；退出／切换身份取消在途请求并拒绝旧身份回包。

游客交接应在服务端事务中使用一次性handoffID，同时迁移订阅、作者关注和经确认的本地对话，不覆盖已有账号；保留显式空订阅，不给第二个账号重复复制。公开→私有的可见性判断必须在每个读取端点实施，不能只依赖搜索索引或缓存失效。

后续收费订阅若加入，使用独立Entitlement／Purchase资源与支付流程，不改变此处免费的角色收藏关系。新增推荐、通知、作者动态与自定义头像资源可按可选字段／独立资源扩展；主版本不兼容时保留迁移与回退路径。
