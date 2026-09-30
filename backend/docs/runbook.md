# 独立开发、测试与上线

## 本机环境

工具已安装：Go 1.27.1、PostgreSQL 17.11、Redis 8.10.2。服务端语言兼容版本在 `go.mod`，精确依赖在 `go.sum`。第一次下载 Go 模块时官方代理在本机网络不可达，使用 `GOPROXY=https://goproxy.cn,direct` 成功下载，未关闭 checksum 校验；该镜像不是运行依赖，其他机器可用默认官方代理。

```bash
cd backend
make dev-up
source .local/environment
make integration
```

脚本只管理 `backend/.local/` 内这套开发服务：数据库 `starry`、测试库 `starry_test`，随机口令存权限 0600 的环境文件。数据库与 Redis 都只监听 loopback。不要把 `.local/environment`、数据库目录、测试捕获或带令牌的 HTTP 日志提交。

已有进程时 `make dev-up` 不杀进程抢端口；修改代码后用 `make dev-down`、`make dev-up` 重启。数据一直保留。需要从零建立测试数据时也不应执行全库清空，集成测试会自行清理其 UUID 账户和 Redis 前缀。

本轮后半程终端权限收紧，旧数据库进程仍占用共享内存，但受限终端无法使用其端口和进程控制；脚本将失败原因留在 `.local/logs/`。不要删除 `postmaster.pid`、数据库文件或共享内存来掩盖这种权限问题。必须在具有普通本机网络/进程权限的开发会话中复测。CoreSimulator 与 Swift 宏插件同样需要系统服务权限。

## 环境变量

| 名称 | 用途 |
| --- | --- |
| `STARRY_ENV` | `development`、`test`、`production` |
| `STARRY_LISTEN` | 默认 `127.0.0.1:8090`；容器中 `0.0.0.0:8090` |
| `DATABASE_URL` | PostgreSQL URI；生产必须单独指定 `sslmode=verify-full` |
| `REDIS_URL` | Redis URI；生产使用 `rediss://` |
| `REDIS_PREFIX` | 同一 Redis 上的环境隔离，默认 `starry:` |
| `DB_POOL_SIZE` | 2..200，默认 16；按副本总数核算连接预算 |
| `ALLOW_TEST_GUEST` | 仅测试/开发可打开，生产必须 false |
| `AI_UPSTREAM_URL` | 可选的私有 worker origin；不允许用户名、查询串、路径 |
| `AI_SERVICE_TOKEN` | 可选服务间凭证，必须与 worker `client_token` 一致；仅服务端保存 |
| `TEST_DATABASE_URL` | 只给集成测试使用的 `*_test` 库 |
| `TEST_REDIS_URL` | 只给集成测试使用，推荐单独实例或 DB |

AI 的两个环境变量要同时配置或都不配置。未配置时账户功能照常运行，AI 代理返回 503。不要为了账户联调重新付费设计音色；现有音色和 Key 留在原私有目录。

角色公开资料走 `GET /v1/ai/characters/{id}/profile`，只返回明确的公开字段。完整 AI 调教测试检查走 `POST /v1/ai/testing/characters/{id}/inspector`：Go 仅允许 `development` / `test`，`production` 一律 404；私有 worker 还必须显式开启默认关闭的 `enable_test_inspector`。身份由既有账户会话转写，不能由客户端指定其他 owner。该接口只读且不调用付费模型；详细开关、数据范围与客户端入口见[角色设定检查](../../docs/design/2026-09-30-character-settings-and-source-idle.md)。

## App 联调

模拟器使用 `http://127.0.0.1:8090`。在仓库根运行：

```bash
python3 scripts/configure_platform_client.py --platform simulator --url http://127.0.0.1:8090
bash scripts/build_host.sh
```

真机需要把 `STARRY_LISTEN` 改为可从局域网连接的监听地址，客户端使用 Mac 的 `.local` 名称，例如 `http://your-mac.local:8090`。设备与模拟器分别生成连接文件，不能把模拟器 loopback 文件当成真机配置。正式部署改为 HTTPS。服务端不依赖这些脚本；它们只是 iOS 联调配置。

测试步骤：新游客 → 修改主题/字号/音量/记忆 → 注册保留资料 → 退出 → 登录恢复 → 第二个账户隔离 → 断网修改后恢复 → 两客户端改同一版本观察冲突 → 重新登录或另一设备恢复。启动自动问候会使用真实 AI，所以自动测试传 `--ui-testing` 等已有测试参数；未明确加 `--live-ai` 的自动化禁止付费调用。

已有体验账户、旧聊天文件不会删除。直接登录一个已存在服务端账户不会把当前游客记录塞给它；注册新账户可以接收当前游客记录。旧 A/B 本机体验账号与正式 UUID 账户分开。

## 数据库与发布

```bash
cd backend
make build
# 配置运行环境或通过秘密管理服务注入环境变量
./bin/starry-migrate
./bin/starry-api
```

`starry-migrate` 使用 PostgreSQL advisory lock，适合发布阶段单独 Job。API 不执行迁移。部署顺序为：备份/验证恢复 → 兼容性迁移 → 新 API 版本 → 就绪探针 → 客户端灰度。回滚优先回滚 API 镜像，保留兼容的新增列；不能把 Goose down 当成无损回滚工具。

生产拓扑为 HTTPS 入口 → 多个 Go API 副本 → 私网托管 PostgreSQL/Redis；AI worker 独立部署。`deploy/Dockerfile` 只 COPY 当前后端目录，distroless 非 root 运行，`deploy/compose.yaml` 是开发工具。云服务器、证书与托管数据库尚未配置，这些命令没有被执行到公网。

健康检查：`/health/live` 只检查进程；`/health/ready` 检查 PG/Redis。`/metrics` 在私网采集。不要向公网暴露 metrics、Redis、PostgreSQL 或 AI 管理路由。入口代理需支持 SSE 无缓冲与 WebSocket 升级；常规 JSON 请求 15s，AI 路由最长 180s，客户端取消会传到 worker。

会话存在 Redis，配置 AOF 与 `noeviction`。Redis 丢失后用户需重新登录，账户资料仍在 PG；Redis 不可用时 API 返回 503，不降级成不验证会话。PG 备份应使用受控的 `pg_dump`/托管快照与恢复演练，异地备份和保留周期由正式环境决定。

## 合约、验证与排错

- `make openapi` 从类型注册生成，离线可运行。修改接口后检查生成差异，不手改生成文件。AI 流事件细节继续由 `services/character_ai` 的协议定义负责。
- 409 是版本冲突，先拉取再三方合并，不无限重试原版本。429 读取 `Retry-After` 或稍后重试。401 重新登录，本机未同步数据保留。
- UUID 消息重复保存不重复插入；日志不得输出令牌、密码、对话全文或包含口令的数据库 URI。
- `/me/export` 是分页账户变更导出，含版本与墓碑，不是把全部资料一次塞进内存。客户端应按 cursor 写到自己的文件；主动清空的历史消息正文已从该流移除。
- 私有角色给非主人返回 404；自己的角色通过会话主体判断，不能使用请求里的 ownerID。公开原生角色元数据会去掉私有 ownerID 和可伪造 authorID。
- 常规请求上限 256 KiB，JSON 文档合并后 64 KiB，记忆/片段 16 KiB，同步页事件正文约 1 MiB。需要新增大对象时增加对象存储协议，不直接取消全部限制。
- `go test -race ./...` 中真实数据库用例明确 SKIP，不能据此声称集成测试通过。必须执行 `make integration` 并保留实际结果。
- `TestReplicaWorkload` 用两个实例、32 并发客户端、16 账户执行 320 条写入并检查归属，输出 p50/p95/p99。这是受控功能负载，不是生产容量认证。

当前本机源代码检查与运行限制见 [验证记录](../../docs/verification/account-platform/README.md)。
