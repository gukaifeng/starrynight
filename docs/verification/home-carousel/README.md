# 固定首页与横向角色选择 · 小伴 0.13.2 / build 25

## 页面与交互

首页移除纵向 ScrollView 和多行网格，改为固定画布：品牌/账号/关于、问候标题、角色预览、分页圆点及聊天/定制/角色设定操作。角色逐页左右切换，四个圆点也可直接选择；纵向拖动不会滚动页面或打开角色。从互动舞台、聊天或设置返回，保留当前选中的角色。首页预览复用图片资源，不启动四个 Unity 场景。

竖屏以中央大卡片展示角色与介绍，底部操作固定；横屏采用左侧问候/角色资料/操作、右侧横向预览，适配 iPhone 17 与 iPad Pro 11-inch。账号、关于、角色设定仍走统一弹窗；角色取景锁不受本轮变更影响。

## 设计决策

沿用 frontend-design 技能既有品牌方向：暖白 #F7F5F0、浅玉 #B8D5C5、卡片 #EAF2ED、深绿 #274A43、次要字 #5B7168、浅桃 #E7BCAD。标题使用系统 Rounded Medium，角色名 Rounded Semibold，说明/操作保留系统正文和 caption。首页的重点是固定框架中的大幅角色预览，不再把选择变成上下找按钮。

采用 Apple 原生 [PageTabViewStyle](https://developer.apple.com/documentation/swiftui/pagetabviewstyle) 和绑定选择；没有添加第三方翻页库。降低动态效果时，圆点切换动画改为短缓动；分页圆点保持 40×44pt 点击区域和独立无障碍名称/选中状态。相邻页面对辅助功能隐藏，防止误打开屏外角色。

原有 thumbnailScale 为小卡片的全身图放大比例。首页可选用名为「目录 thumbnail 名 + Portrait」的独立人像资源，存在时按 1 倍显示，不改角色包或运行时模型。初音使用仓库已有真实渲染 `docs/verification/miku/face-editor.png`，原图直接复制到 `MikuThumbnailPortrait.imageset`，避免旧缩略图缺面和放大锯齿；未生成或修改角色外貌。其他角色继续复用目录预览。

## 问题处理与验证范围

- 首轮在首页容器添加测试 identifier，SwiftUI 将父标识传播覆盖子按钮标识；去掉不必要的容器标识，保留各按钮自己的标识。原始失败 `.local/checks/HomeCarousel-iPad.xcresult`。
- 第二轮发现图片 Button 在纵向拖动松手后可能触发打开舞台。改用会在移动后取消的 tap 手势，同时保留无障碍 Button trait 与默认操作；没有添加拦截横向分页的拖动手势。原始失败 `.local/checks/HomeCarousel-iPad-Final.xcresult`。
- iPad 最终交互用例通过 37.589 秒：四角色左滑、圆点跳转、上下滑零误触、固定标题和底部操作、角色资料返回、独立角色包舞台及聊天、保留选中项、横竖屏切换、关于弹窗返回。结果 `.local/checks/HomeCarousel-iPad-TapFix.xcresult`。
- 之后补充初音清晰人像资源；iPhone 使用包含最终预览图的构建复核相同流程，36.181 秒通过，结果 `.local/checks/HomeCarousel-Phone.xcresult`。实际复查手机竖屏、初音新预览及横屏截图。详见 [结构化结果](results.json)。
- 历史测试中依赖首页上下滚动寻找角色的入口已迁移为分页按钮辅助函数；本轮只运行首页专项，不声称整套历史功能测试全部重跑。

## 真机安装

Release 编译与深度严格验签通过，无线安装 success，设备列表独立确认小伴 **0.13.2 / build 25**。自动启动被 iOS 以 Locked 拒绝；手机解锁后点击小伴即可，不能将本轮写成真机已启动。既有数据保留，workspace 保持 device。见 [安装记录](device-installation.json)。

## 截图

- [iPhone 固定首页](phone-01-fixed-home-human.png)
- [iPhone 初音清晰预览](phone-02-page-hatsune-miku.png)
- [iPhone 横屏](phone-03-landscape-miku.png)

- [iPad 竖屏固定首页](ipad-01-fixed-home-human.png)
- [iPad 横屏固定首页](ipad-04-landscape-human.png)
