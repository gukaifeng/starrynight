# 角色封面与紧凑发现页

角色封面展示角色本身及其默认生活空间。十个内置角色各有一张 1024 × 768 的真实 Unity 渲染图，不用生成式图像重新画角色，避免外观和会话模型不一致。已有背景远景素材继续遵循原来的环境来源记录。

## 内容与绑定

- `CharacterCoverCatalog.json` 显式用 `runtimeID` 绑定图片、创建定义的默认环境及裁切焦点。封面使用创建定义，用户之前在会话里保存的房间、性格、语气不会反写封面。
- 本地创建的角色继续使用其基础模型的 `runtimeID`，因此自然继承基础封面。将来支持作者上传封面时，可以增加作者封面资源引用；目前不伪造每个本地实例都有独立新图。
- 发现页完整展示 4:3 封面。资料页使用 106 pt 的短横幅，围绕每张图指定的面部焦点裁切；现有 52 pt 圆头像、20 pt 名字和同排订阅按钮保留，简介与定制入口留在首屏。
- 封面与圆头像是不同用途。头像继续由原肖像系统生成并保持圆形；封面是固定的角色介绍画面。

## 发现与资料

发现页使用两列角色卡，名字、简短邀请语和作者署名放在封面下方。搜索框视觉高度从 44 pt 收到 36 pt。移除单独的“作者”分栏和作者弹窗入口，作者依旧从角色资料进入，作者作品与关注关系继续保留。“关注作者”筛选只筛选角色作品，不是独立的作者栏目。

资料读取 `model.conversationProfile(preserving:)`，由创建定义提供身份，保留该会话允许保留的个人偏好；不把历史个人性格或背景当作作者原始定义展示。会话顶部胶囊末尾增加约 10 pt、50% 不透明度的无边框静音状态图标。SwiftUI 部分不接收手势，由现有 UIKit 容器提供独立静音命中区。

## 生成与验证

`CharacterCoverBuilder.Export` 是 Editor 专用工具：打开已保存场景，克隆每个真实角色，采样已有 Idle，烘焙当前蒙皮姿态，使用该角色的默认环境和灯光，以 4× MSAA 渲染图片。渲染结束重新打开原场景，不保存场景、不导出引擎。原始输出进入原生 Asset Catalog，既有 `generate_host.py` 自动包含新 Swift、JSON 与图片资源。

```sh
unity status --format json --no-banner
unity run /Users/gukaifeng/Documents/ios-app/unity/CharacterRuntime --timeout 600 -- -executeMethod CharacterCoverBuilder.Export -logFile /Users/gukaifeng/Documents/ios-app/.local/logs/character-covers.log
python3 scripts/validate_character_covers.py
```

本次独立图形批次完成十张图片，日志 `CHARACTER_COVERS_PASS count=10`。十张原图均已逐张目视检查，主体面部和衣服可识别，没有占位头像或错误角色。渲染相机、尺寸、环境绑定证据在 `docs/verification/character-covers/render-report.json`。三个修改/新增 Swift 文件已通过 `swiftc -frontend -parse`。App 编译和模拟器截图由主流程统一执行，尚不能以源码检查代替最终屏幕验收。

建议原生回归关注：发现页两列和本地搜索；角色资料封面与角色匹配，首屏定制可触达；资料 → 作者 → 作品 → 资料的返回链；不再依赖已删除的 `discoverMode` 作者分栏；顶部胶囊点击名字与末尾静音分别命中，静音后图标更新；修改个人背景后封面保持作者默认定义。
