# Noema UI 设计规格

本文是 Noema 当前 UI 设计的总规格。它记录全局体验基调、VI 原则、页面体系、组件边界、可访问性和验收要求。具体页面的详细规则应沉淀到 `docs/design/screens/`，避免所有像素参数都堆在一个总文件里。

## 1. 状态

- 当前状态：有效规范，持续维护。
- 当前产品主线：Flutter 移动应用，Android / Samsung 优先验证，iOS 保持支持。
- Home / `境` 页：Flutter 版本已完成真实本地 `境` 列表、进入 `观`、删除确认和创建入口；如需调整，先更新本规格、页面规格或 OpenSpec 任务。
- Import / `入` 页：Flutter 创建 / 追加 `境` 初版已基本完成，Android 走轻量媒体管线。当前 Android 导入保留系统 Photo Picker，第一次导入时申请图库读取权限用于本地索引、缩略图预热和派生图恢复；后续不要把它重新改回 picker 中转页、自研图库浏览器或整理入口。
- Observe / `观` 页：Flutter 主视图已落地，包含真实比例照片墙、真实时间排序、密度 / 双指缩放、追加照片、多选移除、境名编辑、照片查看器、系统返回规则和 `甄 / 赏 / 鉴` 的 `intent-seal` 底部意图轴。
- Cull / `甄` 页：Flutter 快甄和对照甄已完成首轮实装，支持相似组列表、上下拖动决策、横向召回缩略图、单图 / 双图预览、决策撤销和清除出境。
- Appreciate / `赏` Viewer：v1 规格已确认，定位为从 `观` 进入的单一沉浸式照片欣赏 Viewer；点击底部中间 `赏` 进入，默认从当前 `观` 排序列表第一张开始，不继承 `观` 筛选；把 `赏` 拖到当前可见照片 tile 后松手，可从该照片开始进入；底部只保留播放范围、顺序 / 随机、播放 / 暂停、播放间隔、横竖屏五项控制。
- Appraise / `鉴` 页：Flutter 正式首版工作台已落地，包含 `微瑕 / 成片 / 佳作 / 珍藏` 动态分档、真实比例照片墙、排序、珍藏、单张鉴赏 sheet、AI Provider 设置、单张 AI 品鉴、系列品鉴和结果持久化。
- 方形动作语言：Home 创建、Import 添加 / 完成、Observe 空态添加和 Observe 底部体验入口已统一为方形玻璃签按钮体系，圆形 FAB 不再作为当前默认主动作形态。
- 本地持久化：当前使用轻量 JSON store 保存 `境`、照片元数据、预览路径和决策状态；Android 派生缩略图 / 预览写入应用文件目录 `noema_media/` 并可按单张照片恢复；尚不是 Drift / SQLite 数据库。
- HTML 原型：只保留为历史视觉参考，不再作为“先实现、再迁移到 Flutter”的主流程。

优先阅读顺序：

1. `docs/README.md`
2. `docs/development/ui-development-standard.md`
3. `docs/design/ui-design-spec.md`
4. `docs/design/noema-vi.md`
5. `docs/design/screens/home.md`
6. `docs/design/screens/import.md`
7. `docs/design/screens/observe.md`
8. `docs/design/screens/cull.md`
9. `docs/design/screens/appraise.md`

## 2. 设计工作流

任何 UI 设计、UI 实现或视觉精修都必须遵守：

1. 开始前先判断是否需要使用 Comet / OpenSpec。
2. 阅读本文件和相关页面规格。
3. 复用既有 VI、字体、图标、布局、动效和交互规则。
4. 新页面、新组件、新视觉规则、新交互或新动效确认后，先同步文档，再实施或最小范围同步实现。
5. UI 实现采用 Flutter-first：直接在 Flutter 中开发，用 Flutter Web 浏览器预览快速迭代，再用 Android `emulator-5556` 或真机复核平台差异。
6. 不把重要 UI 决策只留在代码、截图、聊天记录或本地记忆中。

## 3. 产品体验基调

Noema 是一个本地优先的私人照片整理工作台，不是清理工具、文件管理器、仪表盘或 AI 聊天产品。

核心方向：

```text
私人照片助手。
安静、克制、照片优先。
算法辅助，用户做最终决定。
```

应当呈现：

- 极简、安静、留白充足；
- 真实照片承担主要情绪和色彩；
- 专业但不冰冷；
- AI 能力通过流程和措辞自然出现，不通过机器人形象或聊天入口出现；
- 对删除、清理、评分等概念保持谨慎；
- 信任感来自用户可控、解释清楚和不自动破坏系统相册。

避免：

- 清理 App 式焦虑话术；
- 紫色 AI 渐变、机器人图标、赛博视觉；
- 照片评分游戏化；
- 统计面板和状态卡片主导首屏；
- 夸大算法能力；
- 自动删除或暗示 Noema 已替用户做最终审美判断。

## 4. Noema VI 总则

正式 VI 细节见 `docs/design/noema-vi.md`。本节只保留跨页面必须遵守的原则。

- 核心气质：安静的黑白记忆空间，照片承载情绪。
- 主题字系统：`境`、`入`、`观`、`甄`、`赏`、`鉴`。`记` 暂作为记录层概念保留，不作为当前顶级页面优先设计。
- 主题字不是装饰贴纸，也不是标题徽章，应作为低对比度空间层融入背景。
- 主题字使用共享的视觉锚点；不同汉字在字体内的字面留白不同，如需校正只能在共享组件内少量处理，不能让各页面单独手调位置。
- 页面 chrome 应尽量安静：小型 wordmark、图标型工具、少量文字、明确的触控区域。
- real photo content 是视觉重量中心，装饰渐变只能做极弱气氛。
- light / dark 是同一 VI 的两种表达，不应变成两套产品风格。

主题字含义：

```text
境  Home / memory spaces
入  Import / bring photos into a space
观  Space view / all photos and function entrance
甄  Cull / compare and choose what is worth keeping
鉴  Appraise / rate or mark photo value
赏  Immersive viewing / quiet full-screen appreciation
记  Record layer / what was decided, inside later workflows
```

## 5. 字体

Flutter 实现必须依赖打包字体资产，而不是平台 fallback。

- 英文 `Noema` wordmark：`NoemaLatin`，资产为 `assets/fonts/CormorantGaramond.ttf`，来源 Cormorant Garamond，OFL 授权。
- 中文展示文字：`Luo`，Flutter 字体资产为 `assets/fonts/Luo-Regular.ttf`。
- `assets/fonts/Luo-Regular.woff2` 仅作为 HTML / Web 原型参考资产保留；Flutter 原生和 Web 构建都注册 ttf，避免 Android 回退系统中文字体。
- 大型中文主题字、Home 中文 `境` 名称等使用 `Luo`。
- Import 等页面的英文展示型输入占位可使用 `NoemaLatin`，避免英文 copy 回落到系统 sans 或被中文字体撑宽。
- 普通操作标签、辅助文字、按钮文字、照片数量、tooltip 和系统状态只要包含中文，都必须显式使用 `Luo`。纯英文界面可使用页面规格指定的 `NoemaLatin` 或平台 UI 字体。
- Flutter 主题必须配置 `fontFamilyFallback: ['Luo']`，作为系统 Tooltip、旧占位页和未显式设定字体文本的中文兜底，避免 Android 回退系统中文字体。
- 字体命名必须在 `pubspec.yaml`、Flutter 代码、设计规格和开发规范中保持一致。

## 6. 色彩与表面

色彩方向：

```text
vi.light.background       暖白 / 纸白
vi.light.text             柔和炭黑
vi.light.themeMark        极低透明度浅石墨
vi.light.surfaceGlass     半透明暖白

vi.dark.background        近黑暗房炭色
vi.dark.text              暖白
vi.dark.themeMark         黑中见黑的低对比石墨
vi.dark.surfaceGlass      半透明深炭色
```

表面规则：

- 使用细边线、微弱边缘光和克制阴影表达层级。
- 不使用重玻璃拟态、亮色光晕或装饰性渐变作为主视觉。
- 删除、危险和清理相关颜色要克制，避免制造焦虑。
- 背景纹理只能极弱；如果在 Flutter / Android 上读成明显格子，应删除或极大降低透明度。

## 7. 图标与布局

- 正式页面必须保持同一套页面骨架：移动端主画布最大宽度、背景、顶部品牌锚点和主动作位置应统一。
- 正式页面必须使用同一套场景度量和色调来源；顶部 `Noema` 的高度、中心点、背景渐变和 light / dark / auto 色调不能由各页面硬编码分叉。
- Flutter Web 预览时，Home / `境`、Import / `入`、Observe / `观` 等核心页面都应收进同一手机画布，不允许一个页面居中窄屏、另一个页面横向铺满浏览器。
- `Noema` wordmark 是跨页面品牌锚点，默认在顶部居中。左右工具按钮通过占位或 Stack 布局保持它不被推偏。
- 页面主动作优先使用底部方形玻璃签按钮。创建、导入、确认和一字体验入口等同一层级动作应共用方形玻璃表面、固定命中区、中心对齐和克制阴影，不在不同页面随意改成另一种按钮体系。
- 无照片、无可执行对象或上下文未满足时，不必为了版式平衡强行显示确认按钮；空态应优先保留一个明确的添加入口。
- 工具入口优先使用图标，不使用冗长文字按钮。
- 图标必须放在固定尺寸按钮盒中，并按按钮盒居中。
- 自定义 painter 若复刻 SVG，必须保留 `viewBox` 坐标语义，再按 Flutter 实际画布缩放。
- 不允许把 `24 × 24` 坐标直接画到 `22 × 22` 画布，避免图标视觉偏心。
- 固定格式组件必须定义稳定尺寸，避免选中、hover、加载或文本变化造成布局跳动。
- 文字不得与按钮、图标、照片、网格、安全区或系统导航栏重叠。

## 8. 页面体系

当前信息架构方向：

```text
Home
→ Import
→ Observe
   ├─ 甄
   ├─ 赏
   └─ 鉴
```

页面定位：

- Home / `境`：进入或创建照片记忆空间。
- Import / `入`：创建一个 `境`，并把用户主动选择的照片带入其中。
- Observe / `观`：进入一个 `境` 后查看全部照片，并承载后续体验入口。
- Cull / `甄`：进入照片甄选体验，在其中进行相似、连拍或待确认照片的本地甄别与取舍，替代原 `辨` / A-B Arena 的顶级命名方向。
- Appraise / `鉴`：对照片进行本机初见、AI 品鉴、系列品鉴和主观珍藏，替代 `评`，避免工具化打分感。
- Appreciate / `赏`：全屏沉浸式观看照片，替代“静观”；v1 是单一 Viewer，不做多模式功能集合；`展` 暂留给未来对外展示或分享场景。
- Record / `记`：作为 `甄`、`鉴` 过程中形成的记录层或结果状态，不作为当前顶级页面优先设计。

当前 Flutter 代码中 `Processing` 仍承载 `观` 的实现，`Review Groups` route 已承载 `甄` 的当前实现。`A/B Arena`、`Results` 等早期 route / placeholder 命名仍存在，但不应被视为当前产品命名来源。

每个正式页面都应有独立页面规格，记录职责、允许内容、禁止内容、关键组件、交互、空状态、可访问性和验收方式。

## 9. Home / 境 基线

Home 详细规格见 `docs/design/screens/home.md`。

已确认的 Home 职责：

1. 进入已有 `境`。
2. 创建新的 `境`。

当前 Flutter 版 Home 已确认的视觉和交互基线：

- 小型 `Noema` wordmark。
- `Noema` wordmark 顶部居中，右侧工具不应把品牌锚点推偏。
- 大型低对比度 `境` 背景主题字。
- poker-stacked photo covers。
- `境` 名称位于封面下方。
- 顶部图标工具入口。
- 2 / 3 / 4 列显示密度。
- 最近 / 名称 / 创建时间排序。
- 底部居中方形玻璃 `+` 创建按钮。
- 长按 `境` 只暴露删除确认。
- 删除确认必须明确说明不会删除系统相册原照片。

当前 Flutter 版顶部存在 light / dark / auto 色调切换按钮。它是本轮视觉预览和主题复核控件，不应被后续误读为新的核心产品能力；如果发布版本要保留、隐藏或移动，需要单独确认。

Home 不应出现：

- `相册集` 这类文件管理标题；
- 欢迎语、状态卡片、照片数量、进度、更新时间；
- AI 助手气泡、机器人、聊天入口；
- 搜索框、头像、账号身份块；
- 底部导航；
- 手动排序、重命名、换封面等管理入口；
- 清理工具式口吻。

## 10. 组件登记

已确认 Home 组件：

- `NoemaWordmark`：小型英文 wordmark，使用 `NoemaLatin`。
- `NoemaThemeMark`：大型中文主题字，使用 `Luo`，作为背景空间层，并提供跨页面统一视觉锚点。
- `PokerAlbumCover`：2-3 张真实照片堆叠的记忆空间封面。
- `DisplayOptions`：显示密度和排序设置面板。
- `NoemaSquareActionButton`：共享底部方形玻璃签动作按钮，支持一字标签或图标、固定视觉卡片、固定命中区、细边线、上下短线纹样、轻 blur 和克制阴影。Home 创建、Import 添加照片、Import 完成创建、Import 预览关闭、Observe 空态添加和 Observe `甄 / 赏 / 鉴` 入口都应使用同一组件语言，仅内容、位置、尺寸层级和可用状态不同。
- `NoemaFloatingActionButton`：兼容旧调用名的底部动作封装，当前内部委托给 `NoemaSquareActionButton`。后续新增底部主动作时应优先直接使用或复用方形签语言，不再把旧名字理解为圆形 FAB。
- 低亮可点动作：需要低亮但仍给出原因反馈的动作，可显示非阻断轻提示；低亮可点状态在 light / dark 色调下仍必须让图标、边框和方形轮廓清晰可辨，不能淡到像不可见控件。
- `DeleteDialog`：长按后的删除确认。

已确认 Import / `入` 组件：

- `JingNameField`：境名输入，必填，最多 10 个汉字字符感知长度；空值时在 `为境命名` 右侧显示轻量闪烁输入光标。
- `ImportEmptyState`：无照片时的安静添加入口。
- `ImportThumbnailGrid`：4 列导入缩略图滚动区。
- `ImportPreview`：点击缩略图后的放大预览，必须完整显示横图或竖图，关闭入口放在图片下方并留出明确间距。
- `NoemaMediaPicker`：Android 轻量媒体桥。导入阶段只返回 URI 和真实元数据；缩略图、较大预览按需生成，不能在列表阶段复制或解码整批原图。
- `SelectionToolbar`：长按多选后替换目的文案和照片计数的取消选择、删除入口；不把选择态文字拼到顶部 `Noema` 旁边。
- `RemoveImportDialog`：从本次 `境` 暂存区移除照片的确认。

已确认 Observe / `观` 组件：

- `ObserveHeader`：境名、照片数量和照片墙工具行；工具优先图标化，排序首版只提供时间正序 / 时间倒序。境名可通过低权重编辑图标原地改名，编辑态才显示 10 字限制计数。不要加入名称排序或修改时间排序；未来 `鉴` 产生评分后，可以增加评分排序并提供正序 / 倒序。
- `ObservePhotoWall`：稳定自然比例瀑布流，保留横竖图自然比例，同一密度下列宽稳定，使用稳定 id 做密度切换重排。100 张以上照片时启用动画降级和可视区域构建，照片墙仍是 `观` 的主体，底部入口只能轻覆盖，不使用明显暗遮罩压缩中间观看面积。
- `ObserveDensityControl`：紧凑墙、标准墙、大图墙三个离散级别；双指缩放和密度按钮都吸附到这些级别。
- `ObserveExperienceDock`：底部 `甄 / 赏 / 鉴` 功能入口区，只做入口，不自动进入整理或旧 review 流程。当前收敛方向为 `intent-seal`：`赏` 是中间吸附的方形玻璃签，点击进入 `赏` Viewer；v1 默认从当前 `观` 排序列表第一张开始，不继承 `观` 筛选。用户只有从中间 `赏` 起手并向上拖到当前可见照片 tile 后松手，才可从该照片开始进入 `赏` Viewer；命中反馈只作用于当前目标 tile。从底部 `甄` / `鉴` 位置起手时，手势锁定为底部意图轴选择，不转成照片墙命中。用户拖向底部两侧时，中签沿轴移动并在到达两侧后替换为 `甄` / `鉴`，松手触发对应任务并回弹到中轴。`甄` 与 `鉴` 不是常驻同级按钮，只在对应能力可用时以低亮字签、隐章角标、淡虚线和从 `赏` 向两侧传递的脉冲提示存在任务；提示文案在对应图标上方轻量淡入和缩放，并与实际目标中心对齐。保留 `lens`、`object`、`intent`、`intent-ripple`、`intent-tiles`、`intent-rail`、`intent-gate`、`quiet`、`balanced`、`orbit`、`rail` 作为历史对照或后续实验入口，但不再作为当前默认设计。
- `ObserveCullAvailability`：`甄` 入口可用性概念。Import 创建 / 追加完成后，当前 workspace 的本地精筛结果决定 `甄` 是否浮现；轻量信号用时间、批次、文件名序列、EXIF 和尺寸识别连拍 / 同场景候选，视觉信号用多哈希、HSV 颜色、亮度布局和 SSIM 识别相似组，短时间同场景合并只在时间和视觉安全线同时满足时生效。`甄` 是处理入口，不是扫描入口；当前不做应用启动时全图库后台筛选，也不把首次扫描推迟到用户点击 `甄` 后。
- `ObservePhotoViewer`：点击照片进入全屏查看，按需加载更大预览，支持左右滑动、双击放大 / 复位、双指缩放和缩小退出；不显示评分、删除系统照片或编辑入口。
- `ObserveSelectionToolbar`：长按照片进入多选移除状态，隐藏照片墙工具行并显示取消和移除入口；确认后只从当前 `境` 移除，不删除系统相册原文件。
- `ObserveEmptyState`：无照片时只提供方形玻璃添加照片入口，不显示确认按钮、统计卡片或整理进度。
- `ImportAppendMode`：从 `观` 添加照片进入，只显示当前境名和已有照片数量，缩略图区只展示本次准备追加的照片，确认后回到 `观`。
- `NoemaHintBubble`：统一的轻提示胶囊，用于 Import 命名提示和 Home 二次返回退出提示；暗色底、细边框、小圆角、紧凑 padding，不带冗余图标。
- `NoemaBackNavigation`：Android 系统返回和手势返回统一进入业务路由。Home 首次返回显示上半部轻提示，短时间内第二次返回才退出；非 Home 页面返回上一级业务页面。

已确认数据与存储组件：

- `NoemaMediaPicker`：Android 轻量媒体桥，返回 URI 和真实元数据，缩略图 / 大预览按需生成。
- `NoemaLocalStore`：本地 JSON snapshot store，保存 workspace 列表、当前 workspace、照片元数据、预览路径和决策状态；Web 使用 localStorage，原生端使用应用文件目录。

已确认 Cull / `甄` 组件：

- `ReviewGroupsScreen`：相似组复核入口，显示可处理组和空状态。
- `FastCullMode`：快甄模式，当前照片上下拖动到出境 / 保留区域，决策后进入横向召回缩略图条。
- `CompareCullMode`：对照甄模式，竖屏左右两张照片并排比较，最后单张居中。
- `CullPreviewOverlay`：单图大图预览，复用 `观` 的图外点击 / 系统返回关闭逻辑，不显示关闭按钮。
- `ComparePairPreviewOverlay`：对照甄成对同步预览，两张照片同步缩放 / 平移，使用轻量轨迹和贴边描边表达来源。

已确认 Appraise / `鉴` 组件：

- `AppraiseScreen`：鉴工作台页面，显示动态分档、照片墙、排序、AI 设置入口和空态。
- `AppraisePhotoWall`：复用 `观` 的真实比例 masonry 布局，保留横竖图自然比例。
- `AppraiseViewerOverlay`：在全屏照片查看器上叠加可拖动鉴赏 sheet，组织 `初见 / 四维 / 总观 / 打磨 / 自问`。
- `AppraiseBandPicker`：使用半透明横线、渐变和文字组成的分类栏，不使用卡片按钮。

已确认 Appreciate / `赏` 组件：

- `AppreciateViewer`：从 `观` 进入的单一沉浸式照片欣赏 Viewer，复用全屏照片查看器的 contain 展示、左右滑、按需预览恢复和缩放能力；Viewer 自己管理播放范围、顺序 / 随机、播放 / 暂停、播放间隔和横竖屏。
- `AppreciateControlLayer`：底部唯一控制区，使用半透明黑色胶囊和轻 blur；控制条上方使用无数字页位指示器，不显示数字页码。控制项只允许播放范围、顺序 / 随机、播放 / 暂停、播放间隔、横屏 / 竖屏。
- `AppreciateRangePanel`：轻量多选面板，支持 `微瑕 / 成片 / 佳作 / 珍藏`，默认全选，禁止空范围；`微瑕 / 成片 / 佳作` 复用 `鉴` 的分档逻辑，`珍藏` 是叠加标签。

后续基础组件仍需在对应页面规格中逐步正式化：

- `记` 记录层与结果状态；
- Empty / permission / unavailable asset states。

## 11. 文案与本地化

Noema 跟随系统语言。首批支持：

- 简体中文 `zh`
- 英文 `en`

当前本地验证以中文系统语言为基线。所有用户可见字符串应通过本地化层维护；资产名、调试样例名和文件名可作为数据值保留。

文案原则：

- 冷静、事实、具体。
- 说明用户选择范围和本地处理边界。
- 不夸大算法，不暗示自动删除。

可用表达：

```text
这一组适合一起复核。
这组照片很相似，建议选出最值得保留的照片。
这些分析在本机完成。
不会改动你的相册。
```

避免表达：

```text
AI 已经帮你删掉差照片。
一键清理所有废片。
```

## 12. 决策词汇

MVP 决策词汇保持一致：

```text
Keep
Maybe
Review for removal
```

如果紧凑按钮需要更短标签，可以显示 `Review`，但数据和结果桶仍使用 `Review for removal`。除非产品/UI 明确变更，不使用 `Reject` 作为用户可见词。

## 13. 动效

动效用于帮助用户理解方向、比较和进度，不制造表演感。

- `观` 可以通过照片墙、轻量状态和功能入口表达这个 `境` 的当前状态。
- `甄` 过渡应快速、安静、方向明确。
- 决策反馈应清晰但不炫目。
- Home 选项面板、列数切换、按压反馈使用短时、低幅度动效。
- 必须尊重 reduced-motion；非必要动效应可关闭或降低。

## 14. 可访问性

最低要求：

- 深色和浅色模式下文本对比度可读。
- 主要触控目标不小于 44px / dp。
- 状态不能只靠颜色表达。
- 图标按钮必须有语义标签或 tooltip。
- 决策按钮必须通过文字区分，不只靠颜色。
- 文字不得被照片、遮罩、系统栏或浮层遮挡。

## 15. 实现状态

### Flutter Home / 境

当前 Flutter Home 已作为 Noema VI 的第一条落地基线：

- 使用 `NoemaLatin` 和 `Luo` 字体资产。
- 使用本地保存的真实 `境` 列表和照片封面；没有 `境` 时显示安静空状态。
- 移除了 Flutter 里过重的底部网格纹理。
- 自定义图标 painter 已按 viewBox 缩放，避免视觉偏心。
- `+` 创建入口保留 Home → Import 流程。
- `+` 创建入口使用方形玻璃签按钮语言，与 Import / Observe 的底部主动作保持一致。
- 点击已有 `境` 会激活对应 workspace 并进入 `观`。
- 长按 `境` 只暴露删除确认，且不会删除系统相册原照片。

注意：历史 Home 样例照片资产只作为视觉 / 测试参考。真实 `境` 封面必须保持当前 poker-stacked 语言，不把 Home 变成文件管理列表。

### Flutter 主流程

当前 Flutter 主流程已经从早期占位路线收敛到：

```text
Home / 境
→ Import / 入
→ Observe / 观
   ├─ 单张照片查看器
   ├─ 追加 Import / 入
   ├─ Cull / 甄
   ├─ Appreciate / 赏
   └─ Appraise / 鉴（原型 / 实验入口）
```

早期 `Processing` route 仍作为代码兼容层承载 `观` 的实现，`Review Groups` route 已承载 `甄` 的当前实现。`A/B Arena`、`Results` 等早期 route 仍存在，但不应被视为当前产品命名来源。后续正式精修 `赏`、`记` 或把 `鉴` 从原型推进到正式结果系统时，必须先补对应页面规格和数据边界。

## 16. 验收

普通 UI 变更：

```text
dart format lib test --set-exit-if-changed
flutter analyze
flutter test
```

Home 或平台可见 UI 变更还应补充：

```text
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173
flutter build apk --debug
```

Android 截图和安装默认使用 `emulator-5556`。不要使用 `emulator-5554`。

截图、HTML 原型和 `output/` 产物只是验证证据，不是规范来源。规范来源以本文件、`docs/design/noema-vi.md`、`docs/design/screens/`、`docs/development/` 和 OpenSpec 为准。
