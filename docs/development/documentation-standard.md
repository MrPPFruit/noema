# Noema 文档规范

本文定义 Noema 文档目录的用途、语言、协作边界和更新规则。所有说明文档默认使用简体中文。

## 1. 文档语言

- 产品说明、设计说明、开发规范、协作规范和索引必须使用简体中文。
- 代码标识、命令、文件路径、API 名称、字体族名称和第三方许可证名称可以保留英文原文。
- 如果引用历史英文材料，应补充中文说明，避免把英文旧文档当作当前规范。

## 2. 目录用途

- `docs/README.md`：文档入口，记录当前开发基调、阅读顺序、验证策略和目录用途。
- `docs/development/`：开发规范、文档规范、验证策略和多人协作规则。
- `docs/design/ui-design-spec.md`：当前有效 UI 设计规格，是 UI 实现和视觉复核的设计来源。
- `docs/design/noema-vi.md`：当前 VI 规范，记录字体、主题字、色彩、图标、照片使用和整体气质。
- `docs/design/screens/`：页面级设计规格。当前 Home / `境`、Import / `入`、Observe / `观`、Cull / `甄`、Appraise / `鉴` 规格分别位于 `docs/design/screens/home.md`、`docs/design/screens/import.md`、`docs/design/screens/observe.md`、`docs/design/screens/cull.md`、`docs/design/screens/appraise.md`。
- `docs/release-versioning.md`：版本线、当前公开 release、tag / APK 命名和发布检查。
- `docs/releases/`：每个公开预发布包的 Release notes，用于 GitHub Release 文案和后续追溯。
- `docs/design/app-icons/`：App 图标候选、源图、导出尺寸和图标设计说明。
- `docs/design/noema-home-html-reference.md`：Home 页 HTML 参考说明，只能作为历史参考。
- `docs/design/prototypes/`：历史原型和临时设计资产，不作为实现主流程。
- `docs/superpowers/specs/`：产品、技术和行为规格，用于说明 WHAT 和重要背景。
- `docs/superpowers/plans/`：实施计划，用于说明 HOW、拆分任务和记录执行路径。
- `openspec/`：Comet / OpenSpec 变更事实，包括 proposal、design、delta spec 和 tasks。
- `output/`：运行或生成产物，不作为规范来源。
- `archive/`：历史项目材料，不作为当前 Noema 方向，除非重新确认。

## 3. Flutter-first 文档基线

当前 Noema UI 文档必须围绕 Flutter-first 主线组织：

- 新 UI 和视觉精修直接进入 Flutter。
- Flutter Web 浏览器预览用于快速迭代和截图对照。
- Android `emulator-5556` 用于移动端复核。
- HTML 原型只能作为历史参考或设计讨论材料，不作为迁移实现主流程。
- Flutter Home / `境`、Import / `入`、Observe / `观` 主体验已基本完成；Cull / `甄` 的快甄和对照甄已完成首轮实装；Appraise / `鉴` 已进入正式首版工作台。文档应固化现状和复核规则，不推动继续扩展已确认页面。

页面规格优先放在 `docs/design/screens/`。总规格只记录跨页面原则和索引，避免一个文件同时承担 VI、页面、组件、prompt、实现状态和验收记录。

## 4. 字体与视觉术语

文档中涉及字体时必须使用一致名称：

- 英文 `Noema` wordmark：`NoemaLatin / Cormorant Garamond`。
- 中文展示文字：`Luo`。

涉及图标和布局时必须说明以 Flutter 最终渲染为准，重点关注固定尺寸、视觉中心、命中区域、网格对齐、安全区和移动端平台差异。

## 5. Comet / OpenSpec 关系

- OpenSpec 记录变更事实和产品行为边界。
- Superpowers specs / plans 记录较完整的规格背景和实施计划。
- 开发规范记录跨任务长期有效的工作方式。
- 文档索引只负责入口和导航，不承载详细产品决策。
- 不涉及产品行为变化的文档整理，不必强行新增 OpenSpec change。

## 6. Dirty worktree 协作

仓库可能存在其他执行者的未提交改动。编辑文档时必须：

- 先查看 `git status --short`。
- 只编辑任务授权范围内的文件。
- 在现有内容上增量整理，不覆盖他人的改动。
- 不修改代码、测试、assets、openspec、output 或设计规格文件，除非任务明确授权。
- 如果发现授权范围外的文档需要调整，在最终说明中列出，不擅自修改。

## 7. 更新检查

每次修改文档后，应快速检查：

- `docs/README.md` 的索引是否能指向最新规范。
- `docs/development/ui-development-standard.md` 是否仍准确描述 UI 开发流程。
- `docs/design/ui-design-spec.md` 是否需要后续由设计规范任务同步。
- 页面级规格是否已经落到 `docs/design/screens/`。
- 新增文档是否和现有目录用途不冲突。
