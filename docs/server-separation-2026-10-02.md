# 客户端仓库移除 Mac 旧服务端

云端 HTTPS `/health/ready` 与 `/health/ai` 在清理前返回正常；独立后端仓库为 `../starrynight-server`，此处不再维护 Go API、Python AI 服务、部署脚本或服务测试。Mac 的旧进程和自动启动项均已停止。用户明确要求切换完成后删除 Mac 旧服务内容，云端快照和账户数据的权威副本以独立服务端为准。

本仓库删除 `backend/`、`services/character_ai/` 及已复制到独立后端仓库的服务安装、部署、音色设计和付费联调入口。Xcode 构建不再导入服务端 Python 代码：`check_character_openings.py` 只核对本地开场脚本、角色归属和已打包 PCM 哈希；模型转换的公开介绍取自客户端的 `CharacterPublicProfiles.json`。历史 AI 媒体制作工具若再次调用，需显式使用相邻的独立服务端仓库，不属于 App 构建。

本机旧 `backend` 数据库与缓存、AI worker 安装与虚拟环境、旧共享连接文件、应用支持目录和迁移快照均已按固定路径清理；未触及 VRChat 原始模型、客户端封面/语音素材、Unity 工程、Xcode 设备缓存或云端配置。`.local/platform-client/{simulator,device}/PlatformConnection.json` 仍指向云端 HTTPS，`config/PlatformConnection.json` 提供公开无密钥的回退地址。

这次清理不触发百炼付费请求。服务器功能及部署回归在 `../starrynight-server` 验证；客户端只运行 Unity/Xcode 和云端连接检查。旧版设计文档中的 `backend/`、`services/character_ai/` 路径是历史记录，不再是可执行的当前入口。
