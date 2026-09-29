# 存储与缓存验证 · 星夜0.32.0 / 49

入口：「我的 → 设置 → 存储与缓存」。支持缓存大小统计、语音／头像／长图分类选择、实际清理、重新计算、空状态、失败提示和使用中／最近分享文件保留。

## 实际完成的检查

iPhone17模拟器、iOS26.4，Simulator Debug。4个XCTest方法全部通过，75.977秒；其中2个方法承载核心数据测试，2个为真实界面流程。

| 项目 | 结果 | 耗时 |
|---|---|---:|
| CacheSettingsUITests/testCacheFileContracts | 27项通过 | 5.152秒 |
| CacheSettingsUITests/testSettingsSelectionCleanupAndRestart | 通过 | 46.937秒 |
| ConversationExportUITests/testExportContractsInIOSRuntime | 563项通过 | 5.752秒 |
| ConversationExportUITests/testRangeStylesPreviewAndSystemShare | 通过 | 18.137秒 |

缓存核心覆盖：真实分配空间、目录缺失、类别选择、未知文件保留、符号链接与链接根目录、重复／空选择、聊天／账号哨兵文件原样保留、导出活跃租约、分享24小时保护跨重启保存、到期清理、取消分享、异常标记保留、语音内存与异步generation失效、清理后的重新缓存、头像清理及重新生成。

UI从真实「我的 → 设置」入口进入。独立CacheReview目录提供可删除与受保护的样本：先只清语音并验证另外两类不变，再清剩余可用部分，检查受保护长图保留且按钮禁用；刷新、返回会话、订阅数量、主动问候及重启后结果均验证。样本仅限DEBUG模拟器显式启动参数，未清理普通用户缓存或持久资料。

长图回归验证范围、Unicode、分页、PNG和取消，并实际执行月夜／暖笺预览、进入系统分享与取消返回。未选择外部收件人或向其他App发送消息。新缓存租约与分享保留不会改变长图内容。

- [缓存核心输出](cache-core-result.txt)
- [长图回归输出](export-core-result.txt)
- [机器结果及手机交付状态](result.json)

## 页面截图

- [缓存占用与分类选择](screenshots/cache-01-cache-overview.png)
- [只清理语音，其他缓存保留](screenshots/cache-02-only-speech-cleared.png)
- [清理完成，最近分享文件保留](screenshots/cache-03-clear-completed-with-share-retained.png)
- [清理后继续会话](screenshots/cache-04-conversation-after-clear.png)
- [重启后重新统计](screenshots/cache-05-cache-after-restart.png)
- [长图系统分享回归](screenshots/export-04-system-share.png)

截图取自功能验收；最终保留时限说明明确为「分享24小时后可清理」，不承诺到点自动删除。

这些占用数字来自测试文件的实际磁盘扫描，属于隔离测试样本，不代表用户手机当前占用。统计限于应用明确管理的三类缓存，不等同于iOS设置中的App完整占用或设备瞬时可用空间。

## 手机与最终版本

Simulator Debug、Device Release及严格验签通过。缓存功能包一次无线安装成功，手机回读星夜0.32.0 / 49。最后仅修改分享保留期限的说明文字后，两平台再次编译通过；向手机同步这一文字修订时连接隧道超时，未重试，也未继续请求启动。手机已具备完整缓存功能，最终说明文字目前在源码和模拟器版本中。普通模拟器已无QA参数运行，隔离CacheReview样本在保存证据后删除。工作区保持device / Release，保留原Bundle ID和用户资料。

## 重跑

```sh
zsh scripts/test_companion.sh EFA3B59D-3939-4659-B60B-123516393F43 \
 'CacheSettingsUITests/testCacheFileContracts(),CacheSettingsUITests/testSettingsSelectionCleanupAndRestart(),ConversationExportUITests/testExportContractsInIOSRuntime(),ConversationExportUITests/testRangeStylesPreviewAndSystemShare()' \
 Storage-Cache-Review
```

使用新的结果名，避免覆盖已有xcresult。测试脚本生成模拟器工作区；结束后真机运行用`python3 scripts/generate_host.py --platform device`恢复。未新增iPad测试或性能采样，不将模拟器通过／手机安装成功描述为真机交互或帧率验收。

实现边界及Apple参考见[方案](../../design/2026-09-29-storage-cache.md)，关键决策见[开发记录E79](../../development-notes.md)。
