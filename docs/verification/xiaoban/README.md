# 小伴 v0.5.1 · 品牌更新验收

用户约束：名称必须使用常用、笔画简单、人人容易认读的汉字。新名称为 **小伴**（小3画、伴7画），对应身边的小伙伴；罗马字标记 XIAOBAN。

## 已完成

- 深绿底色、暖白与浅桃两个相互依偎的对话气泡；与现有温馨聊天空间统一。通过内置 imagegen 生成，完整[提示词](../../brand-image-prompt.txt)已保存。
- [品牌原图](../../../assets/brand/xiaoban-icon-master.png)1254×1254；AppIcon 1024×1024、BrandMark 256×256，均为无 Alpha 的 PNG。
- 系统 App 名称、首页与关于页、加载标识、系统麦克风提示中的品牌称呼、角色介绍、资料导出名称、相关署名文字更新。
- 项目生成器、品牌元数据、当前产品文档同步更新，版本0.5.1/build7。旧图与历史验收文档保留其当时的品牌名称。
- Bundle ID、存储标识和本机语音服务配置沿用现值，没有进行清空或数据格式迁移。

## 验证

- Xcode Simulator Debug 构建通过：`.local/logs/xiaoban-brand-build.log`。
- 检查构建后 Info.plist，CFBundleDisplayName 为“小伴”、版本0.5.1/build7；资源规格及哈希见[构建与资源记录](build-and-assets.json)。
- iPhone17模拟器安装并普通启动成功；人工复核[首页](home.png)和[桌面图标](springboard.png)。
- 当前 App 中文文案扫描没有旧品牌字样；内部音频错误域和持久化键的旧拼写用于兼容，不是界面文案。
- 本轮为品牌修改，未新增功能测试或重复执行模型／音频全流程。此前偶发的模型启动超时仍按[原验收记录](../atmosphere/README.md)保留，未在此次品牌更新中修复。
