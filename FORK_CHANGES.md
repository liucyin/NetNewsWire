# Fork 之后的改动：代码定位地图（macOS + iOS）

本文用于快速定位本 fork 新增/修改的功能代码位置，方便后续 AI 或人工快速进入正确文件与入口。

## 1) 共享 AI 层（macOS + iOS 共用）

- `Shared/AI/AISettings.swift`
  - Provider Profiles（Base URL / API Key / Model / Rate Limit）
  - Summary/Translation 的 prompt、输出语言、自动翻译/标题翻译/hover 翻译开关
- `Shared/AI/AIService.swift`
  - OpenAI 兼容 Chat Completions 请求（summary/translate 统一走这里）
- `Shared/AI/AICacheManager.swift`
  - Summary/Translation/标题翻译缓存（按 articleID 存/取）
- `Shared/AI/AIServiceErrorExtensions.swift`
  - AI 错误的 `LocalizedError` 文案

## 2) macOS：Preferences → AI（Summary / Translation）

- `Mac/Preferences/AI/AIPreferencesViewController.swift`
  - Summary/Translation 两个 Tab 的 UI 搭建与绑定
  - Translation Tab 的布局修复（checkbox/下拉框/按钮避免压缩堆叠）
  - Hover 翻译开关与 Modifier（Control/Option/Command）选择

入口（打开偏好设置时创建 VC）：
- `Mac/Preferences/PreferencesWindowController.swift`

## 3) macOS：AI Summary / AI Translate（主窗口入口 + 快捷键）

- `Mac/MainWindow/MainWindowController.swift`
  - 主窗口工具栏按钮与动作：`aiSummary(_:)`、`aiTranslate(_:)`
- `Mac/MainWindow/Keyboard/MainWindowKeyboardHandler.swift`
  - 将快捷键映射到 `aiSummary:`、`aiTranslate:` selector
- `Mac/AppDefaults.swift`
  - 快捷键保存（UserDefaults）、默认值、相关开关

## 4) macOS：文章 Detail WebView（Hover 翻译 + 注入/切换原文）

> Hover 翻译链路：Native 监听 modifier → 取当前 hover 段落 → 执行翻译/显示原文 → HTML 注入/缓存。

- `Mac/MainWindow/Detail/DetailViewController.swift`
  - `.flagsChanged` 本地事件监听（edge-trigger）：按下 modifier 才触发一次 hover 动作
- `Mac/MainWindow/Detail/DetailWebViewController.swift`
  - Hover 翻译相关核心方法（命名可能会随重构略变，但都集中在这个文件）：
    - 段落稳定标识：`ensureStableIDs`
    - 监听 hover：`injectHoverListener`
    - 执行 hover 动作：`triggerHoverActionFromHoveredElement`
    - 翻译注入/切换原文：`injectTranslation`、`prepareForTranslation`、`showTranslationLoading`

## 5) macOS：图片查看器（全屏/全窗口 Overlay、关闭按钮、缩放/拖拽手势）

- `Mac/MainWindow/Detail/main_mac.js`
  - 将文章内容区 `img` 点击路由到 native viewer（并给图片加 `zoom-in` cursor）
- `Mac/MainWindow/Detail/DetailWebViewController.swift`
  - `ImageViewerOverlayView`：全窗口 Overlay、右上角关闭按钮、缩放/拖拽、cursor（张开手/抓取）
  - `setUsesFullWindow(_:)`：全屏/全窗口模式下关闭按钮布局
  - `scrollWheel(with:)`：滚轮缩放灵敏度与小幅滚动处理

## 6) macOS：General → Refresh on Launch（功能修复）

- `Mac/AppDelegate.swift`
  - 启动时刷新逻辑（读取 `AppDefaults.shared.refreshOnLaunch`）
- `Mac/AppDefaults.swift`
  - `refreshOnLaunch` 默认值与持久化
- `Mac/Base.lproj/Preferences.storyboard`
  - “Refresh on Launch” UI 绑定

## 7) 缩略图/首图提取增强（用于部分站点没有显式 imageLink 的情况）

- `Shared/Extensions/ArticleUtilities.swift`
  - `Article.imageLink`：当 `rawImageLink` 不可用时，从 HTML 的 `<img ...>` 中提取可用 URL（含 data-src/srcset 等）

## 8) iOS：Settings → AI（新增）

- `iOS/Settings/AIPreferencesView.swift`
  - iOS 的 AI 设置页（SwiftUI）
- `iOS/Settings/SettingsViewController.swift`
  - 将 “AI” 入口 push 到 `UIHostingController(rootView: AIPreferencesView())`
- `iOS/Settings/Settings.storyboard`
  - 新增 “AI” section（注意如果你后续再改 storyboard，section index 会受影响）

## 9) iOS：文章页 AI 操作（Summary / Translate）与 WebView 注入

- `iOS/Article/ArticleViewController.swift`
  - 文章工具栏 AI 菜单入口：`configureAIToolbarItem()`、`runAISummary()`、`runAITranslate()`
- `iOS/Article/WebViewController.swift`
  - Summary/Translation 的注入与恢复（无 hover，按按钮触发）
  - 常用入口：`performTranslation`、`injectTranslation`、`injectAISummary`、`restoreAIStateIfNeeded`

## 10) iOS 17.5.1 支持（Deployment Target）

- `xcconfig/NetNewsWire_project.xcconfig`
  - `IPHONEOS_DEPLOYMENT_TARGET = 17.5`
- `xcconfig/NetNewsWire_iOSwidgetextension_target.xcconfig`
  - `IPHONEOS_DEPLOYMENT_TARGET = 17.5`

## 11) CI：构建 DMG / IPA（GitHub Actions）

- `.github/workflows/build_dmg.yml`
  - macOS DMG 构建（通常以 tag `vX.Y` 或手动触发）
- `.github/workflows/build_ipa.yml`
  - iOS **unsigned** IPA 构建（`workflow_dispatch` 或 tag `ios-v*`）

---

## 附：在 Xcode 的 iOS 模拟器上运行（建议流程）

1. 打开 `NetNewsWire.xcodeproj`。
2. 顶部 Scheme 选择 `NetNewsWire-iOS`。
3. 右侧运行目标选择一个 iPhone Simulator（iOS 17.5/17.5.1 没有也没关系，用更高版本也能跑）。
4. `Cmd+R` 运行。

若你希望“模拟器系统版本也严格是 17.5.x”：
- Xcode → Settings/Preferences → Platforms（或 Components）→ 下载对应 iOS Simulator Runtime（例如 iOS 17.5）。

