# 发布验证

状态：当前公开仓库透明文档。

## 发布前必须确认

- 公开仓库 URL。
- release tag。
- App version。
- GitHub Release 类型：draft、pre-release 或正式 release。
- 是否上传 APK。
- 是否需要 signed tag。
- 是否仍使用 `v0.1.0-beta.1` 作为首次公开版本。
- 本机是否已准备 `android/key.properties` 和对应 release keystore。

## 本地验证

```bash
flutter analyze
flutter test
flutter build apk --release
```

## 安全与隐私验证

- 敏感文件扫描。
- 敏感字符串扫描。
- Android 权限检查。
- 网络请求检查。
- 日志脱敏检查。
- 连接测试机安装并启动验证。

## 产品展示素材验证

- 公开展示素材目录：`docs/assets/showcase/`。
- README 首屏图、截图 strip、主题图、`赏 / 鉴 / 赋` 细节图和竖版预览视频均能在 GitHub 页面打开。
- 字体许可证。
- 图标原创性和品牌边界。
- 公开仓库不包含私人旅行照片源文件或示例素材目录。
- 产品截图 / 视频中不出现私人路径、设备号、真实账号、真实 API Key、通知栏隐私信息或不适合公开的人物细节。

## APK 验证

发布 APK 时需要提供：

```bash
shasum -a 256 noema-android-vX.Y.Z-release.apk
```

release notes 应包含 APK 文件名、SHA256、Android package name 和已知限制。

如果没有 `android/key.properties`，`flutter build apk --release` 可能仍可产出本地 debug-signed release 包；该产物不能上传到官方 GitHub Release。
