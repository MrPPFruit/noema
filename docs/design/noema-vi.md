# Noema VI 规范

本文记录 Noema 当前确认的视觉识别基调。它是 UI 设计规格的 VI 分册，用于约束页面视觉、字体、颜色、图标和气质，不承载具体页面的完整布局参数。

## 1. 核心定位

Noema 是私人照片助手，不是清理工具、文件管理器、仪表盘或 AI 聊天产品。

核心视觉概念：

```text
安静的黑白记忆空间。
照片承载情绪。
主题字成为空间气氛，而不是标题装饰。
控件保持近乎无声。
```

设计关键词：

- 极简；
- 克制；
- 照片优先；
- 私密；
- 高级但不炫技；
- 东方感可以存在，但不做传统装饰；
- AI 通过流程和措辞出现，不通过机器人或聊天界面出现。

## 2. 主题字系统

Noema 使用一字主题作为页面精神锚点：

```text
境  Home / memory spaces
入  Import / bring photos into a space
观  Space view / all photos and function entrance
甄  Cull / compare and choose what is worth keeping
鉴  Appraise / rate or mark photo value
赏  Immersive viewing / quiet full-screen appreciation
记  Record layer / what was decided, inside later workflows
```

当前顶级信息架构优先使用 `境 / 入 / 观`。进入某个 `境` 后，`观` 承载照片墙和功能入口，后续体验以 `甄 / 赏 / 鉴` 作为一字命名方向。其中 `赏` 是可反复进入的沉浸观看体验，`甄` 已落地为相似组快甄 / 对照甄处理页，`鉴` 已落地为本机初见、动态分档、珍藏和单张鉴赏 sheet 的工作台；底部入口应体现这种主次关系。`记` 暂作为结果记录层，而不是当前优先设计的顶级页面。

使用原则：

- 主题字是空间层，不是大标题。
- 字形应大、低对比、柔和，部分融入背景。
- 字形可以轻微裁切，但必须仍然可读，不能像误裁的残字。
- 主题字整体应偏向内容轴左侧，但需要保留足够右移，避免半个字消失在屏幕外。
- 页面不应为了主题字增加解释性文案。

## 3. 字体

### 英文 wordmark

- Flutter 字体族：`NoemaLatin`
- 字体资产：`assets/fonts/CormorantGaramond.ttf`
- 来源：Cormorant Garamond，OFL 授权
- 用途：`Noema` wordmark

`Noema` wordmark 应小、安静、优雅，不做大品牌口号式展示。不得依赖系统字体 fallback。

### 中文展示文字

- Flutter 字体族：`Luo`
- Flutter 字体资产：`assets/fonts/Luo-Regular.ttf`
- `assets/fonts/Luo-Regular.woff2` 仅作为历史 HTML 原型参考资产保留
- 用途：大型主题字、Home `境` 名称、需要延续 VI 气质的中文展示文字

普通操作标签、辅助信息、按钮文字和数字只要包含中文，就必须显式使用 `Luo`；纯图标工具和纯英文 UI 可使用页面规格指定的字体或平台 UI 字体，保持移动端清晰度。

## 4. 色彩

Noema 的主色由黑、暖白、柔石墨和照片自身色彩组成。

浅色方向：

```text
background       暖白 / 纸白
text             柔和炭黑
themeMark        极低透明度浅石墨
surfaceGlass     半透明暖白
photoColor       真实照片色彩
```

深色方向：

```text
background       近黑暗房炭色
text             暖白
themeMark        黑中见黑的低对比石墨
surfaceGlass     半透明深炭色
photoColor       稍压暗但仍有真实色彩
```

禁止方向：

- 单一紫色或蓝紫 AI 渐变；
- 清理工具常见的高饱和红/绿对比；
- 大面积金属霓虹；
- 过重毛玻璃；
- 明显装饰格子、光球、斑点背景。

## 5. 表面与深度

- 通过细边线、微弱边缘光和克制阴影表达层级。
- 深色模式优先使用边缘光和照片层叠深度，不依赖厚重投影。
- 浅色模式阴影应更轻，避免卡片化仪表盘感。
- 圆角保持精致，Home 照片卡片当前以 `8px` 视觉半径为基准。
- 浮层可使用轻微 blur，但不能让用户感到界面被装饰效果主导。
- 底部主动作使用方形玻璃签语言：细边线、轻 blur、克制阴影、上下短线纹样和固定命中区共同表达“可触发”，避免回到通用圆形 FAB。

## 6. 图标

图标是安静工具，不是装饰符号。

- 工具图标使用固定按钮盒和固定命中区域。
- 顶部工具按钮当前以 `40 × 40` 作为 Home 基准。
- 选项面板内图标当前以 `22 × 22` 视觉画布为基准，按钮盒为 `44 × 38`。
- 自定义 painter 必须按原始 `viewBox` 缩放，避免偏心。
- 图标应配语义标签或 tooltip。

## 7. 照片使用

照片是 Noema 的主要情绪和色彩来源。

- 封面、缩略图和比较界面应尽量呈现真实照片质感。
- 不用抽象色块代替已确认的照片空间。
- 公开仓库不分发来源不明的样例照片目录；Home 视觉验证应使用授权明确的展示素材或用户本地导入照片。
- 未来接入真实 `境` 封面时，应保持照片堆叠、圆角、边线、阴影和色彩克制的 VI 方向。

## 8. Home 作为 VI 锚点

Home / `境` 是当前第一条正式落地的 VI 基线。

它定义了以下可复用方向：

- 小型 `Noema` wordmark；
- 大型低对比中文主题字；
- 真实照片 poker-stacked 封面；
- 图标型工具入口；
- 底部居中方形玻璃签创建动作；
- light / dark 成对设计；
- 不使用 dashboard、搜索、账号、AI 聊天入口。

后续页面应继承这种“进入记忆空间”的克制方式，而不是回到通用移动工具 App 的界面语言。

## 9. App 图标候选

Noema 第一批 App 图标候选记录在：

```text
docs/design/app-icons/README.md
```

图标方向必须延续当前 VI：安静的黑白记忆空间、真实照片优先、无清理焦虑、无机器人或紫蓝 AI 渐变。当前建议以 `01. 境中照片` 作为第一版主图标候选，后续落地 Android adaptive icon 或 iOS app icon 时再拆分平台尺寸与安全区。
