# 小伴 0.6 · 写实角色与空间验收

本轮新增写实成年女性“小夏”和角色空间定制。图片为 Unity 实际渲染或 Xcode 模拟器截图，不是概念图；编辑器图与模拟器图分别存放，不用于证明真机帧率。

## 功能

- 面容：脸宽、下颌、眼型、唇形、鼻翼，使用实际网格变形。
- 身形：纤细／饱满、腰胯曲线、有限身高变化；毛衣与长裤有对应贴合变形。
- 造型：四种肤色、三种虹膜颜色、两种发型、三种发色、一套针织上装＋长裤及三种上衣配色。
- 空间：晴日客厅、柔光影棚、静夜；光源左右方位、高度、亮度、影子深浅。背景为真实3D几何，地面接收实时阴影。
- 小夏支持挥手、点头致意、打招呼、触头摇头、呼吸待机、眨眼和说话时的基础张口。
- 小夏可从首页“定制”进入；所有角色的顶部调节按钮都能打开背景／光影设置。参数按角色保存，预览可取消，重启恢复。

## 实测证据

- Unity contentVersion6 / studioProtocol1 模拟器导出成功，Xcode Debug 构建成功。
- `Studio-Phone-3.xcresult`：iPhone 17 / iOS 26.4，定制流程通过（47.548秒），0失败。断言读取 Unity 实际回传的 studio 参数，覆盖脸型、体态、短发、静夜、光照角度、保存、取消撤销、杀进程重启恢复和恢复推荐。
- `Studio-iPad-1.xcresult`：iPad Pro 11英寸（M4）/ iOS 26.4，同一定制流程通过（53.480秒），0失败。已目视确认定制时上方模型仍完整可见；截图位于 `ipad-pro-11/`。
- `iphone17/`：该轮 XCTest 原始截图。`02-face-preview.png` 为捏脸预览；`05-room-and-light.png` 为全身背景与光照设置。
- `human-full.png`、`human-portrait.png`、`custom-portrait.png`、`human-wave.png`：Editor 实际材质、变形、背景、动作与光照截图。
- 首轮 UI 测试的失败不是面板没打开，而是根容器标识覆盖子按钮；已用明确的无障碍容器分组修正，失败 bundle 保留在 `.local/checks/Studio-Phone-1.xcresult`。

## 画质与性能边界

皮肤和针织衣物源贴图为2048×2048，眼睛和发丝源贴图为1024×1024；保留贴图真实分辨率，导入上限4096不等于源资源是4K。使用移动端PBR、服装法线、透明发片、原生渲染比例、4×MSAA与实时软阴影。头发是发片/网格，不是逐根发丝模拟；衣服使用骨骼蒙皮与预制变形，不是实时布料物理。未加入高端皮肤次表面散射或照片扫描资产。

这是可运行的第一版写实角色定制，不宣称已达到照片级或电影级真人质量。默认请求120FPS，仍支持60/120切换；本轮未测量新角色在手机持续运行时的实际帧率，不能由模拟器或历史双角色帧率推断。

## 复现与资料

- 资产制作：`scripts/prepare_real_character.py`，使用 `.local/character-venv/bin/python`；工具与官方源包在 `.local/character-tools`、`.local/downloads`。
- 可编辑源：`.local/character-tools/Xia-source.blend`。
- Unity生成：`RealCharacterBuilder`、`CharacterRoomBuilder`，由 `BuildIos.Setup()` 调用。
- 资源出处：`unity/CharacterRuntime/Assets/ThirdParty/MakeHuman/provenance.json`；应用“关于 → 写实角色来源与署名”。
- 关键决策与错误处理：[开发记录 E35](../../development-notes.md)。

## 真机准备状态

Release / iphoneos 签名编译成功，`codesign --verify --deep --strict` 通过，版本0.6.0/build8。使用此前独立小伴的 Bundle ID，不会更新旧模型空间的那份 App。产物与签名有效期见 `device-build.json`。本轮设备显示未连接，因此没有安装到手机，也没有新角色真机帧率测试。workspace 最终保留 device 配置；手机连接后可运行 `bash scripts/run_device.sh DEVICE_UDID`，模拟器体验已保持运行。
