# Noema 版本管理

状态：当前有效规则
更新日期：2026-07-01

## 公开版本线

Noema 的公开版本线从首次公开仓库开始重新命名。

推荐首次公开版本：

```text
Git tag: v0.1.0-beta.1
Release title: Noema 0.1 Beta 1
GitHub Release type: Pre-release
Android versionName: 0.1.0-beta.1
Android versionCode: 11
APK: noema-android-v0.1.0-beta.1-release.apk
Checksum: SHA256SUMS.txt
```

旧的 `v0.2.0-alpha.10` 属于公开前内部 alpha 线，不再作为公开版本命名基准。

## 名称含义

版本号格式：

```text
v<major>.<minor>.<patch>-<stage>.<n>
```

字段含义：

- `major`：重大稳定版本。`1.0.0` 只能由产品负责人明确确认。
- `minor`：一个公开产品阶段。新增明显用户能力、产品结构或发布渠道时递增。
- `patch`：稳定版本后的修补号。公开 beta 阶段通常保持 `0`。
- `stage`：发布阶段。当前公开首版使用 `beta`。
- `n`：同一个阶段内的第几次公开预览。

## 递增规则

公开 beta 阶段默认这样递增：

| 场景 | 下一个版本 |
|---|---|
| 首次公开 beta | `v0.1.0-beta.1` |
| 同一公开阶段的小修、文案、隐私文档、截图、APK 重发 | `v0.1.0-beta.2`、`v0.1.0-beta.3` |
| 明显新增用户可感知能力，例如新的核心流程或重要平台支持 | `v0.2.0-beta.1` |
| 接近正式版，只做发布候选验证 | `v1.0.0-rc.1` |
| 正式稳定版 | `v1.0.0` |
| 正式版之后的 bugfix | `v1.0.1` |

不要在公开 beta 阶段使用 `v0.1.1-beta.1`，除非已经发布过 `v0.1.0` 稳定版，并且正在为 `0.1.1` 做补丁候选。

换句话说：

```text
v0.1.0-beta.1
v0.1.0-beta.2
v0.1.0-beta.3
v0.2.0-beta.1
v0.2.0-beta.2
v1.0.0-rc.1
v1.0.0
v1.0.1
```

## GitHub Release 类型

首次公开版本建议使用 GitHub Pre-release。

含义：

- 仓库和 release 都公开可见。
- 用户可以下载 APK、验证 SHA256、提交 issue。
- GitHub 会标记它不是稳定正式版。

默认流程：

1. 先创建 draft release。
2. 上传 release-signed APK 和 `SHA256SUMS.txt`。
3. 人工检查 README、隐私说明、release notes、APK 文件名和校验值。
4. 发布为 pre-release。

不要把首次公开 beta 标记为正式 latest release。

## Android 版本规则

Android 有两个版本概念：

- `versionName`：用户看到的版本名，例如 `0.1.0-beta.1`。
- `versionCode`：Android 用来判断能否升级的内部整数。

`versionCode` 必须持续递增。虽然公开版本线从 `0.1.0-beta.1` 重新开始，当前公开首版仍应使用 `versionCode: 11` 或更高，因为公开前内部包已经到 `0.2.0+10`。

后续规则：

```text
v0.1.0-beta.1 -> versionCode 11
v0.1.0-beta.2 -> versionCode 12
v0.1.0-beta.3 -> versionCode 13
v0.2.0-beta.1 -> versionCode 21 或继续递增到 14
```

当前建议使用简单递增整数，不提前设计复杂编码。等进入多渠道发布后再升级规则。

## APK 发布规则

GitHub Release 建议上传：

```text
noema-android-v0.1.0-beta.1-release.apk
SHA256SUMS.txt
```

不要上传：

- debug APK。
- 未签名 APK。
- 签名密钥。
- AAB。AAB 主要用于 Google Play，不适合 GitHub 用户直接安装。

## Release Signing

官方 GitHub Release 必须使用 release signing，不上传 debug-signed APK。

本地签名配置使用 Flutter / Android 常见的 `android/key.properties`，该文件被 `android/.gitignore` 排除，不进入公开仓库：

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=...
```

没有 `android/key.properties` 时，Gradle 会回退到 debug signing，让贡献者仍然可以本地运行 `flutter build apk --release`。这个回退产物只能用于本地验证，不能上传到官方 release。

## 历史说明

公开前内部 alpha 线：

```text
v0.2.0-alpha.10
0.2.0+10
```

这条线保留为内部开发历史，不继续作为公开版本命名规则。

`v0.2.0-alpha.10` 是 `v0.2.0-alpha.9` 后的 UI 与 AI Provider 收口包，包含 `甄`、`赏`、`鉴` 当前主流程、Android 图库权限和 AI Provider 文档等能力。公开首版从 `v0.1.0-beta.1` 重新命名，但 Android `versionCode` 继续递增。

## 发布检查

- `flutter test`
- `flutter analyze`
- `flutter build apk --release`
- 安装到测试机并启动验证
- 生成 SHA256
- 敏感信息扫描
- release notes 说明用户可见变化、隐私 / 网络行为变化、验证方式和已知限制
