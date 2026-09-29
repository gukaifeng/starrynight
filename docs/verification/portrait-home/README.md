# 小伴 0.16.0 / build 29 · 轻量界面与角色头像

20:56 已完成 iPhone 17 无线更新、版本回读与自动启动，手机为 **0.16.0 / 29**；沿用原 App 和数据。见[脱敏安装记录](device-installation.json)。当前 workspace 保持 device / Release。

## 本版结果

- 返回角色页不再先拆除聊天和暂停 Unity，也不再用 UIKit 截取 Metal 画面盖回首页；完整可见窗口连续淡出后再清理。保留减少动态效果适配。
- 返回、定制的可见底片缩至 34 pt、白色透明度 32%，命中范围仍为 44 pt。
- 输入栏顺序为文字 → 语音 → 发送；发送圆底 32 pt、轻边框，键盘收起操作移到键盘工具栏。
- 首页唯一横向单卡，约 300 × 358 pt；头像不超过 144 pt，分页指示在卡片上方，横屏采用横排卡片。
- 四个默认头像由实际模型生成。保存定制后自动生成 512 × 512 头肩头像，按角色和外观缓存；不会把远景截图或聊天动作当头像。首版沿用已有模型契约，见[模型制作约定](../../character-standard/02-model-production.md)。

## 已执行的验证

| 设备 / 结果包 | 内容 | 实际结果 |
| --- | --- | --- |
| iPhone 17 / PortraitHome-Phone-01 | 紧凑首页、我的/关于、统一定制及气泡长按 | 两项通过；同包的首次头像测试失败，不将整包标成通过 |
| iPhone 17 / PortraitHome-Phone-02 | 四角色各进出两次、返回后当前角色、横屏卡片 | 44.673 秒通过；同包的造型切换测试失败，不将整包标成通过 |
| iPhone 17 / PortraitHome-Phone-03 | 输入按钮几何顺序、保存短发后头像改变、重启保留 | 31.475 秒，一项、零失败 |
| iPhone 17 / PortraitHome-Phone-04 | 最终分页修正后的左右滑动、返回选角、横竖屏 | 61.934 秒，一项、零失败 |
| iPad Pro 11 英寸 M4 / PortraitHome-iPad-01 | 四角色各进出两次、头像位置尺寸、横屏布局 | 46.699 秒通过；同包首次滑动分页失败 |
| iPad Pro 11 英寸 M4 / PortraitHome-iPad-02 | 左右滑动、固定主体、返回选中角色、横竖屏与账号 | 57.337 秒，一项、零失败 |

初轮发现缓存头像刷新会使 TabView 选角跳动，改为保留选择的横向分页 ScrollView。第二轮在定制子页切换中立即点分段按钮未切到造型，补充子页层级和等待实际子页出现，再完整验证保存、返回和重启。iPad 实际录像还发现第二次小范围滑动停留在原角色，改为按卡片对齐的 viewAligned 并限制单次分页，重跑完整分页流程通过。失败结果保留在本机，没有删除后只报告成功。

10 项原生关闭/栏目路由逻辑检查通过。Unity 代码编译、模拟器导出与真机导出通过；新增 portraitRevision 1 构建门禁，阻止新宿主混用没有头像功能的旧引擎。没有新增第三方依赖。

返回过程已录制并抽取连续画面检查，可见整窗逐渐淡出；截图和 UI 断言不能证明任何设备上绝无单帧闪烁。本轮没有测量真机持续帧率，也没有重跑全部历史功能。

## 实际截图

[聊天页按钮与输入栏](01-quiet-controls-and-composer.png) · [默认头像](02-default-portrait.png) · [保存短发后的匹配头像](03-saved-short-hair-portrait.png) · [重启后保持相同头像](04-portrait-restored.png) · [iPad 竖屏初音](05-ipad-portrait-miku.png) · [iPad 横屏](06-ipad-landscape-home.png) · [iPhone 初音单卡](07-phone-miku-home.png) · [iPhone 横屏](08-phone-landscape-home.png)

## 复现与证据

原始日志、结果包、录像保存在 Git 忽略的 `.local/`，共享目录只保存截图和脱敏结果：

- `.local/checks/PortraitHome-Phone-01.xcresult`
- `.local/checks/PortraitHome-Phone-02.xcresult`
- `.local/checks/PortraitHome-Phone-03.xcresult`
- `.local/checks/PortraitHome-Phone-04.xcresult`
- `.local/checks/PortraitHome-iPad-01.xcresult`
- `.local/checks/PortraitHome-iPad-02.xcresult`
- `.local/checks/portrait-home-phone.mp4`
- `.local/checks/portrait-return-sequence.png`

```bash
python3 scripts/export_unity_ios.py --platform simulator
zsh scripts/test_companion.sh SIMULATOR_ID PortraitHomeTests PortraitHome-Repeat
```

默认资源生成使用打开 ViewerScene 的 Unity Editor，执行 `CharacterPortraitBuilder.Export()`；生成后编译宿主。用户的保存外观由 App 自动处理，无需重新编译。
