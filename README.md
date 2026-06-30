# Noema

Noema 是一个移动端私人照片整理工作台，目标是帮助用户在自己的设备上完成快速筛选、沉浸浏览和可选的 AI 品鉴。

状态：公开 beta 准备中
适用版本线：首次公开版本采用 `v0.1.0-beta.1`
许可：源码采用 Mozilla Public License 2.0，品牌与素材另行声明

## 当前状态

- 当前公开准备目标：beta 预发布，不承诺稳定 API。
- 当前真实功能：`甄` 快速筛选、`赏` 沉浸浏览、`鉴` 分组评审与可选 AI 品鉴。
- 当前不做的事：不默认后台扫描全图库，不自动删除照片，不默认上传照片到云端。

## 核心原则

- 用户主动选择照片，Noema 才建立整理空间。
- 默认整理流程发生在本机。
- Noema 提供算法辅助和品鉴建议，但最终取舍由用户决定。
- AI 品鉴是可选能力，不是 Noema 的默认入口，也不是聊天助手。

## 隐私与 AI 边界

- 照片整理默认发生在用户设备上。
- AI 品鉴只在用户主动配置 Provider 与 API Key 后触发。
- API Key 保存在设备安全存储中，公开仓库不会包含任何密钥。
- AI 请求发往用户配置的 Provider，不经过作者服务器。
- Noema 不承诺第三方 Provider 的隐私政策；用户需要自行确认所选 Provider 的数据处理规则。

## 下载与验证

首次公开 release 尚未创建。发布前需要人工确认：

- 公开仓库 URL。
- release tag 与 App version。
- GitHub Release 是 draft、pre-release 还是正式 release。
- 是否上传 APK。
- APK 文件名与 SHA256。

## 构建

```bash
flutter pub get
flutter test
flutter build apk --release
```

发布前还需要运行 Android 签名、权限、网络请求和素材授权检查。

## 开源许可

采用：

- 源码：Mozilla Public License 2.0。
- Noema 名称、Logo、图标、截图、商店素材、包名和 bundle id：不随 MPL-2.0 授权。
- 产品截图、手机框展示图、视频和设计参考素材：按各自来源单独声明。
- 公开仓库不提供私人旅行照片样例包。

## 参与贡献

早期公开仓库优先欢迎：

- 可复现 bug report。
- 测试用例。
- 文档修正。
- 隐私、权限、构建和发布验证问题。

大型产品方向、云同步、账号系统、追踪分析、广告 SDK、默认上传照片等改动，需要先开 issue 讨论。

## 支持开发

未来可以通过 GitHub Sponsors 支持独立开源开发。Sponsor 不代表购买商业 SLA、定制开发、优先修复或长期维护承诺。
