# 变更日志

状态：当前公开仓库说明。

## Unreleased

- 暂无。

## v0.1.0-beta.2 - 2026-07-02

- 新增 `鉴` 页面长按选择、删除和批量删除照片。
- 新增照片详情 sheet 中的单张删除入口。
- 统一删除确认弹窗，与既有删除体验保持一致。
- Android 删除流程支持仅从 Noema 移除，或在用户确认后同时删除系统相册原图。
- 修正 Android release 构建签名配置，本地 release keystore 存在时使用官方 release 证书。
- 更新 Android release 版本号到 `0.1.0-beta.2+12`。

## v0.1.0-beta.1 - 2026-07-01

- 发布首次公开 GitHub pre-release，并提供 release-signed Android APK 与 SHA256 校验信息。
- 同步 README 当前状态、下载入口和公开仓库 URL。
- 更新 GitHub README 首页为 `Noema / 境语` 品牌叙事。
- 增加 `docs/assets/showcase/` 产品展示图与 32 秒竖版预览视频。
- 补充 Android release signing 配置和发布阻断说明。
- 整理公开仓库 README、隐私、安全、贡献、品牌和第三方声明草案。
- 修正 Noema 当前叙事为“移动端私人照片整理工作台 + 可选 AI 品鉴”。
- 修正 AI Key UI 文案，使其与设备安全存储行为一致。
- 补充敏感信息、产品展示素材、网络请求和版本号确认门。

## 当前公开 release 策略

当前公开 release 采用：

- tag：`v0.1.0-beta.2`。
- App version：`0.1.0-beta.2+12`。
- release 类型：GitHub pre-release。
- APK：上传 release-signed APK。
- SHA256：提供 `SHA256SUMS.txt`。

后续公开 release 前仍必须最后确认：

- 公开仓库 URL。
- 是否需要 signed tag。
- release notes 与 APK 文件名。
