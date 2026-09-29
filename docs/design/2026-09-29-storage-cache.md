# 存储与缓存 · 星夜 v0.32.0 / build49

入口为「我的 → 设置 → 存储与缓存」。显示本机应用管理的缓存占用、语音／头像／长图三项分类，可勾选清理、重新计算，展示实际删除的大小。默认全选；没有可清理文件时禁用按钮。清理是可再生成文件的直接操作，不增加重复确认弹窗。返回、重新进入和前后台恢复重新扫描；不显示伪进度或把未读取的文件当作零占用。

视觉延续月白深色：夜底#101114、层#1E2025、墨白#EEF3F6、柔金#D6C3AA、次字#ABAEB9；32pt圆体数字、14pt正文、11–12pt说明。三个类别共用一张紧凑分组卡，44pt以上操作范围，扫描时仅替换右上刷新图标为进度指示；不遮住整个页面。没有装饰性百分比、假容量圆环或修改模型取景。

## 清理边界

| 类别 | 目录与允许文件 | 清理后 |
|---|---|---|
| 语音 | Library/Caches/SpeechClips-v1 内64位哈希名.wav | 清除内存副本；后续播放重新合成，已有文字和时长记录保留 |
| 角色头像 | Documents/CharacterPortraits 内.png/.json | 清除内存图像及键；先显示内置头像，进入对应会话后按保存的外观重新生成 |
| 对话长图 | tmp/ConversationImages 内UUID子目录的.png/.jpg及分享保留标记 | 删除未在使用的导出／预览副本，原聊天、系统照片和用户另存文件保留 |

不扫描或整目录删除Documents、Application Support、全部Caches、全部tmp或App Bundle。账号、作者、角色订阅、聊天、记忆、定制、迁移备份和内置模型／语音资源均不进入清理列表。不修改用户主动导出的JSON资料。未知文件、符号链接和非约定子目录跳过；根目录为链接或读取失败显示部分统计提示。删除前再次检查路径与链接，不追随链接访问其他资料。

优先读取totalFileAllocatedSize统计磁盘分配占用，缺失时回退fileSize；数值按文件相加，不冒充系统设置的完整App占用或设备立即增加的可用空间。iOS自行管理的引擎／系统缓存未列入应用可清理项。

## 并发与使用中保护

CacheStorage为后台actor，统计、清理、导出文件租约注册和自动过期清理由同一actor串行处理。文件遍历不在MainActor运行，清理完成重新扫描；部分失败明确报告，成功数值只来自实际删除成功的文件。重复清理幂等，零字节文件仍可删除。

语音清理同时推进缓存generation并清空NSCache，清理中和清理前启动的异步合成不能在完成后把旧结果写回。实际播放使用内存Data，清理磁盘不删除聊天或中断音频。头像清理取消待捕获请求、清空内存并暂缓接受新结果，清理后按当前可见会话重新请求；不发送取景、角色切换或姿势命令。

长图在创建目录前获得租约，导出结果、预览与系统分享项共享租约，最后一个持有者释放时解除保护。准备系统分享时写入24小时保留标记，跨进程／重启仍保护扩展延迟读取；取消分享则解除该标记，当前预览仍由租约保护。最近分享或正在使用的文件计入总占用，但不计入可清理大小，页面明确显示保留大小。失效标记／读取异常保守保留并给出部分统计提示。自动24小时清理同样遵守租约和分享保留期限。

## 验证方式与参考

专用临时目录验证类别、大小、空／重复清理、链接、私有资料保留、活跃租约、分享重启保留／到期／取消、语音旧请求失效和头像重新生成。UI种子使用DEBUG＋模拟器＋显式参数的独立CacheReview目录，避免在自动化中删除普通用户缓存。实际设置入口、分类勾选、清理反馈、刷新、会话返回与重启结果在iPhone17模拟器检查；长图生成与系统分享专项回归覆盖本次租约改动。

按用户约定查询skills目录及ios cache技能；检索结果以联网和通用存储为主，沿用已读取frontend-design及Apple Foundation原生接口，无新增运行依赖。

- [Apple：Using the file system effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)
- [Apple：URLResourceValues](https://developer.apple.com/documentation/foundation/urlresourcevalues)
- [Apple：isSymbolicLinkKey](https://developer.apple.com/documentation/foundation/urlresourcekey/issymboliclinkkey)

实际结果与截图见[验证记录](../verification/storage-cache/README.md)。
