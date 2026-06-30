# Home / 境 页面规格

本文是 Noema Home / `境` 页的页面级规格。当前 Flutter 版 Home 已基本完成，本文用于固化功能框架、UI/UX、VI、资产和验收基线；后续不要在没有新 OpenSpec 或设计确认的情况下继续扩展 Home 功能。

## 1. 页面职责

Home 只有两个长期职责：

1. 进入已有 `境`。
2. 创建新的 `境`。

`境` 是照片记忆空间，不是普通文件夹、相册清理任务或统计面板。

当前 Flutter 版本已完成 Home 视觉外壳、真实 `境` 网格、显示选项、删除确认和创建入口。已有 `境` 点击后会激活对应本地工作区并进入 `观`，不能用 dashboard 或文件管理页临时代替。

## 2. 已确认内容

Home 首屏允许出现：

- 小型 `Noema` wordmark；
- 大型低对比度 `境` 背景主题字；
- 顶部工具图标；
- `境` 封面网格；
- 每个 `境` 的短名称；
- 底部居中方形玻璃 `+` 创建按钮；
- 长按后的删除确认浮层。

Home 不允许出现：

- `相册集`、文件夹、库管理等标题；
- 欢迎语、引导大段文案；
- 头像、账号、会员或身份模块；
- AI 助手气泡、机器人、聊天入口；
- 搜索框；
- 状态、照片数量、日期、进度、更新时间；
- 统计卡片、任务卡片、dashboard 模块；
- 底部导航；
- 手动排序拖拽；
- 重命名、换封面等管理入口；
- 清理工具式语言。

## 3. 功能框架

### 创建

底部 `+` 是创建/导入入口。当前 Flutter 实现保持现有 Home → Import 流程，点击后进入导入页。

规则：

- 按钮只显示 `+`，不显示 `新建` 文本。
- 视觉上保持方形玻璃签、轻 blur、底部居中，并与 Import / `入`、Observe / `观` 的底部主动作共用组件语言。
- 必须尊重 Android 手势导航和安全区。

### 进入已有境

Home 可进入已有 `境`。当前版本点击封面会激活对应 `ReviewWorkspace`，并进入 `观` 主视图查看该 `境` 的全部照片。

规则：

- 点击封面进入对应 `境`；
- 不在 Home 上展开管理面板；
- 不把 Home 改成文件列表或统计页。
- Home 展示的 `境` 来自本地保存的 workspace 列表；没有 `境` 时显示安静空状态，而不是样例相册。
- 封面使用该 `境` 前 1-3 张照片组成 poker-stacked cover；照片不可用时使用克制 fallback。

### 长按删除

长按 `境` 只暴露删除确认。

确认文案：

```text
删除这个境？
不会删除你系统相册里的原照片。
```

危险动作必须使用明确文字确认，不能只靠图标表达。

### 显示选项

顶部显示选项使用图标入口，不使用齿轮。

当前选项：

```text
sort: 近 / 名 / 时
layout: 单个排布图标循环 2 / 3 / 4
```

含义：

- `近`：最近活动或最新修改，当前 Flutter 样例数据以 `modified` 表达；
- `名`：名称；
- `时`：创建时间。

默认：

```text
columns: 2
sort: 近
```

显示选项弹框分为两组：

```text
排序              |  排布
近 / 名 / 时       |  单个排布循环按钮
```

重复点击当前排序项可切换升序/降序。排布不显示三个并列按钮，而是复用 `观` 的密度交互：一个图标按钮在 2 / 3 / 4 列之间循环。当前不加入手动排序。

### 色调切换

当前 Flutter 顶部包含 light / dark / auto 色调切换按钮。它用于本轮视觉预览、字体检查和主题复核，不是 Home 长期核心能力。

后续发布决策：

- 保留为用户设置；
- 移入设置页；
- 隐藏为调试入口；
- 或删除。

这些都需要单独确认，不应在本轮继续开发。

## 4. VI 与字体

- `Noema` wordmark 使用 `NoemaLatin`。
- `NoemaLatin` 资产：`assets/fonts/CormorantGaramond.ttf`。
- `境` 背景主题字使用 `Luo`。
- `Luo` Flutter 资产：`assets/fonts/Luo-Regular.ttf`。
- `境` 名称使用 `Luo`，保持与主题字一致的中文气质。
- 普通 tooltip、辅助文案、对话框正文和按钮可使用平台 UI 字体。

不能依赖 Android / iOS / macOS 系统字体 fallback 来“碰巧”接近设计。

## 5. 布局基线

当前视觉基准以 `390 × 844` 移动画布为主要参考，并兼容：

```text
375 × 812
390 × 844
412 × 915
```

结构顺序：

```text
Noema wordmark                         工具图标

大型低对比度「境」融入左侧背景

[poker-stacked cover]     [poker-stacked cover]
name                      name

[poker-stacked cover]     [poker-stacked cover]
name                      name

                         +
```

当前 Flutter 基准：

- 页面最大内容宽度：`390`。
- 顶部内边距：`28`。
- 顶部栏高度：`44`。
- `境` 字：`164px` 视觉字号，`Luo`，低透明度。
- 设置面板位置：右上，靠近顶部工具图标下方。
- 创建按钮：视觉卡片约 `58 × 74`，命中区约 `84 × 92`，底部居中。

## 6. 网格规则

默认 2 列。显示选项可切换 3 / 4 列。

2 列基线：

- column gap：`34`
- row gap：`30`
- grid top padding：`104`
- label：`18 / 22`
- label gap：`12`
- cover scale：`100%`

3 列基线：

- column gap：`18`
- row gap：`28`
- grid top padding：`100`
- label：`15 / 19`
- label gap：`9`
- cover scale：`92%`

4 列基线：

- column gap：`10`
- row gap：`23`
- grid top padding：`98`
- label：`13 / 17`
- label gap：`7`
- cover scale：`86%`

网格切换应平滑重排，不应产生明显跳动或裁切。

## 7. PokerAlbumCover

`PokerAlbumCover` 是 Home 的视觉核心。

规则：

- 每个封面由 2-3 张照片卡片叠放组成。
- 前景照片占主要视觉重量。
- 背景照片轻微偏移和旋转。
- 圆角精致，当前以 `8px` 为基准。
- 深色模式使用边缘光和层叠深度，不依赖重阴影。
- 浅色模式阴影更轻。
- 使用真实照片质感，不使用抽象色块。

历史 Flutter 样例资产：

```text
assets/images/home_albums/
```

这些资产曾用于稳定 Home 视觉复核。当前产品路径应优先使用本地保存的真实 `境` 和真实照片封面；样例资产只作为历史或测试参考，不应重新成为正式 Home 内容。

## 8. 图标与对齐

顶部按钮基线：

- 按钮盒：`40 × 40`
- slider 图标：`25 × 25`
- theme 图标：`22 × 22`

设置面板按钮基线：

- 按钮盒：`44 × 38`
- 图标画布：`22 × 22`

Flutter 自定义 painter 必须按原始 SVG `viewBox 0 0 24 24` 缩放到实际画布。不能直接把 `24 × 24` 坐标画进 `22 × 22` 画布，否则会出现明显偏心。

所有图标需检查：

- 视觉中心；
- 按钮盒中心；
- 触控命中区域；
- 与同排图标的垂直中线；
- active / inactive 状态是否引起布局位移。

## 9. 背景

Home 背景由三层方向组成：

1. 深色或浅色基础渐变；
2. 极弱径向光感；
3. 大型 `境` 字空间层。

历史 HTML 原型曾包含极弱 soft-light 网格纹理。Flutter / Android 上该纹理会读成明显底部格子，因此当前 Flutter 版已移除明显网格，只保留渐变气氛。

未来不得重新加入可感知的装饰格子。

## 10. 空状态

首次没有 `境` 时仍保持极简：

```text
Noema

境

+
```

可选单行：

```text
还没有境
```

隐私、信任和处理范围说明应放在 Import 或删除确认等相关时刻，不作为 Home 常驻说明。

## 11. 验收

普通文档或样式复核：

```text
flutter analyze
flutter test test/features/home/home_screen_test.dart test/app/navigation_flow_test.dart test/widget_test.dart
```

视觉复核：

```text
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173
```

移动端复核：

```text
flutter build apk --debug
```

Android 安装和截图默认只使用：

```text
emulator-5556
```

不要使用 `emulator-5554`。

验收重点：

- `Noema` wordmark 是否使用 `NoemaLatin`；
- `境` 和中文名称是否使用 `Luo`；
- 顶部图标与设置面板图标是否居中；
- 2 / 3 / 4 列切换是否稳定；
- 底部不出现明显格子；
- 删除确认文案准确；
- `+` 仍进入 Import；
- Android 状态栏、导航栏、安全区不破坏首屏。

## 12. 历史参考

历史 HTML 原型和迁移记录：

```text
docs/design/prototypes/noema-home-vi-v1.html
docs/design/noema-home-html-reference.md
```

这些文件只用于追溯早期视觉探索和差异原因。后续 Home 迭代以 Flutter 实现、本页面规格、`docs/design/ui-design-spec.md` 和 `docs/development/ui-development-standard.md` 为准。
