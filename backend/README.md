# StarryNight Platform

星夜的独立 Go 账户与资料服务。这个目录自身就是一个 Go module 和 Docker build context；构建、测试、数据库升级及部署均不需要 Xcode、Unity、角色素材或 Python AI 服务。接口版本为 `/v1`，完整机器可读定义是 [api/openapi.json](api/openapi.json)。

已实现账号密码注册/登录、测试游客与原账户升级、账户资料、改密与注销、全局设置、每角色偏好、角色订阅、作者关注/资料、角色目录与创建/发布、会话隐藏、聊天记录/搜索、记忆/共同片段、增量同步、分页资料导出，以及已有 AI worker 的鉴权代理。微信、短信登录还未接真实供应商；没有伪造这些登录成功。

实现与边界见 [架构设计](docs/architecture.md)，本机和线上操作见 [运行手册](docs/runbook.md)，本轮实际运行结果见 [验证记录](../docs/verification/account-platform/README.md)。最新代码是否已经通过完整联调，以验证记录为准。

## 本机启动

已准备 Homebrew Go、PostgreSQL 17、Redis。首次执行会在 `.local/` 生成随机开发口令，建立独立数据目录；不会使用或清空其他应用的数据库。

```bash
cd backend
make dev-up
source .local/environment
make check
make integration
```

账户 API 为 `http://127.0.0.1:8090`，交互文档为 `/docs`。`make dev-down` 停止这一套本地服务，保留数据。端口为 PostgreSQL 55432、Redis 56379。只有 `ALLOW_TEST_GUEST=true` 时提供“跳过登录，先体验”；创建独立匿名账户，之后可以原地注册，保留同一账户 ID 和资料。生产环境禁止开启该开关。

也可以直接使用容器，不需要 Homebrew：

```bash
cd backend
cp .env.example .env
# 编辑 .env，为本地数据库设置自己的随机口令
docker compose --env-file .env -f deploy/compose.yaml up --build -d
```

Compose 是单机开发拓扑，不能把它当成已经部署的生产高可用集群。

## 日常开发

| 命令 | 用途 |
| --- | --- |
| `make build` | 单独构建 API 与迁移二进制到 `bin/` |
| `make test` | 竞态检测、无外部依赖单测；真实 DB 测试默认明确跳过 |
| `make integration` | 必须连接真实 PostgreSQL/Redis，检查两个 API 实例、账户隔离和并发写入 |
| `make check` | `go vet` + `go test -race` |
| `make openapi` | 从代码生成 OpenAPI，无需数据库、网络或 AI Key |
| `make migrate` | 执行 Goose 升级；API 不在启动时争抢迁移 |

集成测试要求 `TEST_DATABASE_URL` 指向名称以 `_test` 结尾的独立数据库，`TEST_REDIS_URL` 指向测试 Redis。每次使用唯一键前缀，只清理自己创建的账户和键。不会使用 SQLite 或内存仓库冒充真实数据库测试。

CI 为仓库根的 `.github/workflows/backend.yml`，只由服务端路径变化触发。它构建 Linux 二进制与独立容器，并使用真实 PostgreSQL、Redis 运行测试。原生账户协议另有独立 macOS 检查；两者均不下载受限模型，也不会调用付费 AI。

## App 连接

在仓库根目录执行：

```bash
python3 scripts/configure_platform_client.py --platform simulator --url http://127.0.0.1:8090
python3 scripts/generate_host.py --platform simulator
```

手机需要 Mac 的 `.local` 域名或正式 HTTPS 地址；手机上的 `127.0.0.1` 指向手机本身。连接文件只包含服务地址，放在忽略目录；登录令牌由服务端签发并进入系统 Keychain，不打包数据库口令或付费 API Key。

原生入口为“我的 → 账户”。已有本机体验账户可以选择“连接服务端账户”；登录/注册、测试游客、同步状态和冲突处理已写入客户端源码。旧的本机资料不会被作为另一个已存在服务端账户的资料自动上传。新注册账户可以接收当前游客资料；明确切换账户后使用各自缓存。

## 扩展约定

优先添加字段和命名空间扩展，保留未知字段，使用 `schema_version`、资源 `version` 和账户同步游标；语义不兼容的变化使用新主版本。不能承诺未来任意变化都零兼容成本，迁移、契约测试和旧客户端回归始终是发布的一部分。
