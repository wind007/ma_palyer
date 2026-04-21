# ma_player

`ma_player` 是一个基于 Flutter 的 Emby 客户端播放器项目，使用 `video_player + fvp` 作为核心播放能力，支持多端（Android / iOS / Windows）媒体播放与基础媒体库浏览。

## 项目特性

- Emby 服务器管理：支持添加、保存与切换服务器信息。
- 用户认证与会话：基于 Emby 接口完成登录、鉴权与播放会话上报。
- 多版本播放：支持切换不同媒体源版本（清晰度/编码）。
- 音轨与字幕：支持在播放中切换音轨与字幕流。
- 请求头自定义：支持设置 `User-Agent` 与常见 `X-Emby-*` 头字段。
- 主题与基础体验：支持深色/浅色主题与桌面端页面过渡优化。

## 技术栈

- Flutter
- `video_player: 2.9.5`
- `fvp: ^0.30.0`
- `http`, `shared_preferences`, `screen_brightness`

> 注意：本项目当前已固定 `video_player` 与 `fvp` 组合。修改媒体相关依赖前，建议先做兼容性验证。

## 快速开始

### 1) 环境准备

- 安装 Flutter SDK（建议与当前项目锁定版本保持一致）
- 安装对应平台工具链：
  - Android：Android Studio + SDK
  - iOS：Xcode + CocoaPods（仅 macOS）
  - Windows：Visual Studio（Desktop development with C++）

### 2) 安装依赖

```bash
flutter pub get
```

### 3) 运行项目

```bash
# 例如 Windows
flutter run -d windows
```

请从 `lib/main.dart` 作为应用入口运行。

## fvp 集成说明

项目在 `lib/main.dart` 中显式调用了 `fvp.registerWith(...)`，并传入播放器缓冲参数。初始化顺序为：

1. `WidgetsFlutterBinding.ensureInitialized()`
2. 业务管理器初始化（如 `ServerManager`、主题管理）
3. `fvp.registerWith(...)`
4. `runApp(...)`

建议保持该顺序不变，避免出现平台侧播放器初始化时机问题。

## 商店上架时的 fvp 合规与风险清单（iOS / Android / Windows）

以下内容用于降低发布风险，不构成法律意见；正式上架前建议由你或团队做最终法务与商店策略复核。

### A. 许可证与第三方声明

- `fvp`（pub.dev 展示）为 `BSD-3-Clause`，允许商业分发，但需保留版权与许可证声明。
- `fvp` 依赖底层 `mdk-sdk` 二进制能力，发布前应确认：
  - 你实际打包进应用的第三方动态库清单；
  - 对应许可证文本是否已在应用或随包文档中提供；
  - 若使用可选编解码组件（如 FFmpeg 扩展构建），其许可证义务是否满足。
- 建议新增一个 `NOTICE` 或“开源许可”页面，至少覆盖：`fvp`、`video_player`、`http` 等核心依赖。

### B. 商店审核重点（与 fvp 强相关）

- **内容来源合规**：仅播放你有合法授权的媒体内容与流地址。
- **版权风险控制**：不要在商店描述中暗示可绕过版权保护或用于盗版内容分发。
- **加密与网络安全**：确保 HTTPS/TLS 配置合理，避免明文传输账号密码。
- **崩溃与回退策略**：对不支持格式或解码失败场景给出用户可理解提示，避免审核时出现“无响应/黑屏”。
- **后台与权限最小化**：仅申请必要权限，并在隐私政策中解释用途。

### C. iOS / Android / Windows 分平台建议

- **iOS**
  - 使用 Xcode Archive 产物做真机回归，重点检查播放启动、切换音轨/字幕、前后台切换稳定性。
  - 在应用内提供隐私政策入口，说明账号信息、播放行为数据用途（若有上报）。
  - 确认无私有 API、无动态下载可执行代码等违规行为。

- **Android**
  - 覆盖多 Android 版本与芯片机型验证硬解/软解回退路径。
  - 检查网络安全配置与明文流量策略（如 `usesCleartextTraffic`）。
  - 对异常流媒体源提供降级提示，避免 ANR 或长时间黑屏。

- **Windows（Microsoft Store）**
  - 确认 MSIX 打包后第三方动态库完整且可加载。
  - 在商店提交信息中写明媒体播放能力与网络依赖，避免“功能描述不一致”。
  - 做首次启动与弱网场景测试，确保不会因依赖加载失败导致闪退。

### D. 发布前自检（建议逐项打勾）

- [ ] 依赖版本冻结并可复现构建（含 `fvp`）。
- [ ] 第三方许可证与 NOTICE 已准备并可在应用中查看。
- [ ] 隐私政策已覆盖账号、日志、播放行为（如有）。
- [ ] 多平台真机回归通过（播放、切换版本/字幕/音轨、退出与恢复）。
- [ ] 异常场景可回退（网络失败、鉴权失效、解码失败）。
- [ ] 商店文案不涉及版权绕过、破解或侵权暗示。

## 参考链接

- Flutter: [https://docs.flutter.dev/](https://docs.flutter.dev/)
- fvp: [https://pub.dev/packages/fvp](https://pub.dev/packages/fvp)
- fvp 许可证页面: [https://pub.dev/packages/fvp/license](https://pub.dev/packages/fvp/license)
- fvp 源码: [https://github.com/wang-bin/fvp](https://github.com/wang-bin/fvp)
- mdk-sdk: [https://github.com/wang-bin/mdk-sdk](https://github.com/wang-bin/mdk-sdk)

## 合规文档草稿

- 第三方许可声明草稿：`NOTICE`
- 隐私政策草稿：`PRIVACY_POLICY.md`

## 开源代码与品牌资产边界

为避免第三方直接“同名同标”上架，本项目采用“代码与品牌分离授权”策略：

- 源代码许可：以 `LICENSE` 为准（若仓库尚未提供 `LICENSE`，默认不视为授予代码再分发权）。
- 品牌/商标规则：见 `TRADEMARK.md`。
- 品牌素材许可：见 `BRAND_ASSETS_LICENSE.md`（默认保留所有权利）。

若发布衍生版本，请至少更换应用名称、图标、启动图与商店文案，并明确标注“非官方版本”。