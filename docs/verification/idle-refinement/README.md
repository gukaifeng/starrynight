# 可见待机与分组默认 · 0.47.0 / 68

范围：当前发布的琪宝、豆日向，角色包均为 2.2.0；iPhone 优先。实现决策见[设计记录](../../design/2026-09-30-visible-idle-and-defaults.md)。原始角色档案不变，本轮增强明确标为 App 适配。

## 实际变化

| 项目 | 琪宝 | 豆日向 |
| --- | --- | --- |
| 上半身原呼吸幅度 | 4 倍 | 3 倍 |
| Unity 实际导入的头部范围 | 0.663° → 2.652° | 1.251° → 3.753° |
| Unity 实际导入的胸部范围 | 0.845° → 3.382° | 1.595° → 4.786° |
| 单次闭眼／停留／睁眼 | 0.16／0.035／0.26 秒 | 0.16／0.035／0.26 秒 |
| 头发／衣物环境风预算 | 7.5°／3.2° | 7.5°／3.2° |

眨眼总时长约 0.455 秒，间隔数组及初次等待保持上一版。风力预算不等于每条骨链必然转过的角度，最终仍受响应、原链长度、身体碰撞和原 5／7／10 度约束。身体运动只增强 Chest、Head；髋部与下肢不放大。

角色表现各分类首项是「默认表情」「默认待机」「默认手势」「默认耳朵」「默认尾巴」或「默认穿搭」。只恢复当前分类，保留其他类别、角色位置及取景；顶部「全部默认」恢复所有原作默认选择。默认穿搭包括原来就启用的配件。

## 数据与引擎结果

- 四项四元数／GLB 转换测试通过：相对首帧放大、跨 180° 短弧、相反符号四元数、下半身与来源数据保留及拒绝重复放大。
- 全角色包预检通过。与本机上一版 GLB 逐通道比较，琪宝 39 段／866 通道、豆日向 21 段／580 通道保持不变；旧 Idle 对应新 Source_Idle，原 VRC 动作仍保留。见本机 [source-preservation.json](source-preservation.json)。
- 实际 Unity 导入检查通过，共 1,974,580 次断言。两角色分别以 60／120 Hz 步进，检查最终骨骼与眼睑网格、有限值及骨链边界、静态姿势呼吸、表情／睡眠优先、嘴型保留、跨角色复位和非活动角色停止。表情复位保留已选姿势；冻结身体时衣发仍有环境风运动。见 [runtime-review.json](runtime-review.json)。
- Unity 两平台导出均通过，清单为 `autonomyRevision:2`；Simulator Debug 和 Device Release 编译通过，安装包版本均为 0.47.0／68。

60／120 Hz 是数值检查的步进频率，不是手机实际呈现帧率。本轮没有进行持续真机 FPS 测量。

## 模拟器操作验收

iPhone 17／iOS 26.4 的最终 `testVisibleIdleAndCategoryDefaultsPreserveOtherSelections` **通过，113.239 秒，1 项完整双角色流程，0 失败**。结果在 `.local/checks/Idle-Refinement-v047-Verified.xcresult`，日志在 `.local/logs/Idle-Refinement-v047-Verified.log`。

- 两角色各无触摸停留 22 秒，累计眨眼和最终头、胸、发、衣运动量均增加；运行时确认为 revision 2、包 2.2.0、单次眨眼约 0.455 秒。
- 实际点击表达项及坐姿，再点击「默认表情」，引擎返回坐姿仍在、原表情已移除、自动眨眼恢复。再点「默认待机」恢复站立；默认穿搭识别作者初始开启的配件；最后「全部默认」通过。
- 已复核两角色的默认入口与待机截图：琪宝[待机](simulator/anime-kipfel-autonomous.png)、[默认选项](simulator/anime-kipfel-default-option.png)、[表情恢复后仍坐着](simulator/anime-kipfel-expression-restored-pose-retained.png)；豆日向[待机](simulator/anime-mamehinata-autonomous.png)、[默认选项](simulator/anime-mamehinata-default-option.png)、[表情恢复后仍坐着](simulator/anime-mamehinata-expression-restored-pose-retained.png)。各图旁保存同名 runtime JSON。
- 最后恢复无测试参数的普通启动，并保存[待机预览](simulator/idle-preview-compact.mp4)。模拟器日志有 ASTC 纹理不支持而解压的已知回退提示，未见运行异常；没有据此改动设备材质配置。原始录像同目录保留，观看版压缩为 720 像素宽／60 fps，仅供查看动态效果，不作为帧率测量。

## 验证中解决的问题

1. **导入器旧上限拦截新风力**：生成值更新后，导入检查仍限制 4／2 度，首次检查报 `SECONDARY_MOTION_AMBIENT_ANGLE_INVALID`。导入器与运行时改用共同的 8／4 度最大预算常量，保留逐链与碰撞限制，重新实际导出。
2. **横向分类栏的自动化操作**：屏幕外的「穿搭配件」既不能直接点击，也可能在读取 `isHittable` 时就触发 XCTest 错误。测试先按实际 frame 滑动至可见区域，再确认和点击；没有改大界面、移除断言或跳过该分类。
3. **测试产物与执行内容不一致**：一次运行报告成功，但附件仍是旧的 `expression-priority`，没有新版分组默认操作；不能据此认定新功能验收通过。核对本机及模拟器 Runner 二进制已含新测试字符串，替换测试 Runner 并以新的唯一测试方法执行，逐项核对日志和附件。测试脚本之后仅卸载临时 Runner，保留 App 及其数据。
4. **场景重新序列化噪声**：Unity Setup 生成大量局部对象 ID 变动。比对忽略局部 fileID 后的 981 个序列化块完全一致，恢复原场景文件，避免提交无功能变化的万行 diff。

## 手机安装

新版已通过 Wi-Fi 安装到 iPhone 17，设备返回星夜 `0.47.0`／`68`。随后自动启动被系统以 `Locked` 拒绝；没有等待手机或重复请求解锁。用户解锁后直接打开星夜即可。安装成功不代表本轮已在真机中人工复核动画。

设备原始记录留在 `.local/checks/idle-refinement-device-{install,launch,apps}.json`；不公开设备标识及原始角色资源。原始构建、失败轮次与 XCTest 结果留在 `.local/logs/`、`.local/checks/`，本目录大体积图片、视频与 JSON 按仓库规则只保留本机。
