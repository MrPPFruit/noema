<p align="center">
  <img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="Noema app icon" width="120">
</p>

# Noema

[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-public%20beta%20preparing-orange)
![Platform](https://img.shields.io/badge/platform-Android%20first-brightgreen)
![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter)

Noema 是一个本地优先的移动端私人照片整理工作台，目标是帮助用户在自己的设备上完成快速筛选、沉浸浏览和可选的 AI 品鉴。

English: Noema is a local-first mobile photo curation workbench for private photo review, selection, browsing, and optional AI-assisted appraisal.

> 算法辅助，用户做最终审美决定。

## 快速链接

[当前状态](#当前状态) · [功能](#noema-做什么) · [隐私与 AI](#隐私与-ai-边界) · [截图](#产品截图) · [下载](#下载) · [构建](#构建) · [贡献](#贡献)

## 当前状态

Noema 正在准备首次公开 beta：

- 首次公开版本线：`v0.1.0-beta.1`
- 当前平台重点：Android first，iOS 保持工程支持
- 当前 release：尚未发布公开 APK
- Android package name：`com.mrppfruit.noema`
- 官方仓库：[github.com/MrPPFruit/noema](https://github.com/MrPPFruit/noema)

公开 beta 不是稳定版。它适合早期试用、反馈问题和审查隐私 / 构建 / 发布链路，不代表已经进入 `1.0.0`。

## Noema 做什么

| 模块 | 状态 | 说明 |
|---|---|---|
| `入` Import | 已实现 | 用户主动选择照片，创建或追加到一个本地整理空间 |
| `观` Observe | 已实现 | 照片墙浏览、密度切换、多选移除和大图查看 |
| `甄` Cull | 已实现 | 快速筛选、对照甄、相似组辅助和撤销 |
| `赏` Appreciate | 已实现 | 从 `观` 进入的沉浸式照片 Viewer |
| `鉴` Appraise | 首版可用 | 本机分档、珍藏、单张 / 系列 AI 品鉴和结果持久化 |

Noema 不做这些事：

- 不默认后台扫描全图库。
- 不自动删除系统相册原照片。
- 不默认上传照片到云端。
- 不提供内置 AI API Key。
- 不把公开仓库当作照片素材包或二创模板。

## 隐私与 AI 边界

Noema 的默认整理流程发生在用户设备上。只有用户主动配置 AI Provider、Base URL、Model 和 API Key，并触发 `鉴` 的 AI 品鉴时，相关照片数据才会发送到用户选择的 Provider。

| 行为 | 默认发生 | 说明 |
|---|---:|---|
| 本机导入和整理 | 是 | 用户主动选择照片后进行 |
| 后台全图库扫描 | 否 | 不在启动后默认扫描整机照片 |
| 自动删除原照片 | 否 | Noema 不替用户删除系统相册原图 |
| AI Provider 请求 | 否 | 只在用户主动配置并触发时发生 |
| 作者服务器转发 | 否 | AI 请求不经过作者服务器 |

更多细节：

- [隐私架构](docs/privacy-architecture.md)
- [AI Provider 与 API Key](docs/ai-provider-and-api-key.md)
- [网络请求](docs/network-requests.md)
- [发布验证](docs/release-verification.md)

## 权限与网络

| 项目 | 当前公开准备状态 |
|---|---|
| 照片访问 | 通过系统 Photo Picker / 用户主动选择进入 Noema 工作流 |
| 原图处理 | 不自动删除系统相册原图，不把公开仓库作为照片素材包 |
| 网络请求 | 默认整理流程不需要作者服务器；AI 请求只在用户主动配置并触发时发生 |
| API Key | 由用户自行输入，保存在设备安全存储中；公开仓库和官方 release 不内置密钥 |
| Release 验证 | 发布 APK 时提供文件名、package name、SHA256 和已知限制 |

## 产品截图

产品截图和短视频会随 `v0.1.0-beta.1` 发布前补充。公开展示素材会来自真实 App 截图或录屏帧，不会发布原始私人照片文件。

计划补充的公开展示图：

- 首页 / 工作空间入口。
- `入` 导入与命名。
- `观` 照片墙。
- `甄` 快速筛选。
- `赏` 沉浸式查看。
- `鉴` 本机分档与可选 AI 品鉴。

## 下载

公开 APK 尚未发布。发布后只建议从官方 GitHub Releases 下载：

- [Noema Releases](https://github.com/MrPPFruit/noema/releases)

请不要从未知转载链接下载 APK。公开 release 会提供：

- APK 文件名。
- Android package name：`com.mrppfruit.noema`。
- SHA256 校验信息。
- 版本说明和已知限制。

如果后续进入 Google Play、F-Droid 或其他渠道，会在 README 和 release notes 中明确说明。

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

发布构建还需要 release signing。不要上传 debug APK、未签名 APK、签名密钥、keystore 或本机 `local.properties`。

版本号规则见 [docs/release-versioning.md](docs/release-versioning.md)。

## 仓库内容

这个公开仓库包含：

- Flutter App 主体源码。
- Android / iOS / Web 工程文件。
- 字体和 Noema 图标资产。
- 用户向文档、隐私说明、网络请求说明、贡献指南和安全政策。

这个公开仓库不包含：

- 私有开发仓库历史。
- 内部 OpenSpec / Superpowers 过程文档。
- 旧 Tauri archive。
- 本地构建输出、验证日志和 agent 工具产物。
- 私人旅行照片源文件或示例照片目录。
- keystore、证书、真实 API Key、token 或本机路径配置。

## 贡献

早期公开阶段优先欢迎：

- 可复现 bug report。
- 测试用例。
- 文档修正。
- 隐私、权限、构建和发布验证问题。
- 小范围 UI 文案和可访问性改进。

大型产品方向、云同步、账号系统、追踪分析、广告 SDK、默认上传照片等改动，需要先开 issue 讨论。

请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。

## 许可与品牌

- 源码：Mozilla Public License 2.0，见 [LICENSE](LICENSE)。
- Noema 名称、Logo、图标、截图、商店素材、包名和 bundle id：不随 MPL-2.0 授权，见 [TRADEMARKS.md](TRADEMARKS.md)。
- 第三方依赖、字体、图标和产品展示素材：见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 支持开发

未来可以通过 GitHub Sponsors 支持独立开源开发。Sponsor 不代表购买商业 SLA、定制开发、优先修复或长期维护承诺。
