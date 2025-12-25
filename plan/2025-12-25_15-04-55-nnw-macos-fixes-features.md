---
mode: plan
cwd: /Users/ellison/Projects/NetNewsWire
task: NetNewsWire(macOS 15.6) 修复与功能开发（缩略图/悬停翻译/启动刷新/图片查看器/加载优化/自定义快捷键）
complexity: complex
planning_method: builtin
created_at: 2025-12-25T15:04:55+08:00
---

# Plan: NetNewsWire(macOS 15.6) 修复与功能开发

🎯 任务概述

在 macOS 15.6 上，面向 NetNewsWire 现有架构完成 2 个 Fix + 4 个 Feature/Optimize：
1) Timeline 部分 Feed（如“少数派”）文章缩略图不显示（需检查文章内是否有图）。  
2) 悬停段落翻译失败后，即使按 Ctrl（或用户设置的 modifier）也无法重试。  
3) 设置 -> 通用新增“启动后自动刷新”选项。  
4) 图片查看器增强：点击图片最大化、鼠标小手、滚轮缩放、拖拽关闭/平移、右上角 X 关闭；动画丝滑且低 CPU/内存（可评估 `NSScrollView` +（必要时）`CATiledLayer`）。  
5) 在网速允许时优化缩略图/图片加载速度（并发/缓存策略）。  
6) 允许用户自定义快捷键动作（至少覆盖 AI Summary / AI Translate）。

📋 执行计划

Phase 1：建立基线与复现用例（里程碑：可稳定复现 6 个需求点）
- 缩略图：订阅/定位“少数派”等样例 Feed，记录“有图但 Timeline 无缩略图”的文章样本与对应 `contentHTML/summary/rawImageLink` 特征。
- 悬停翻译：在 Preferences > AI 打开 Hover Translation，并设置 modifier（默认 Control），制造失败（例如 provider 配置无效/断网），记录失败后 Ctrl 重试行为与 DOM 状态。
- 图片查看器：确认当前点击正文图片行为（是否走 linkActivated / window.open / 无响应），确定接入点（WebKit message handler + native viewer）。
- 基线验证：后续每个 Phase 完成都要用 `XcodebuildMcp` 做一次可编译验证（macOS scheme）。

## Repro Samples

> 目标：为后续每个 Issue 提供“可在 5 分钟内复现”的最小样例与验证步骤（包含成功/失败路径），并记录必要依赖（网络、AI provider 配置等）。
>
> 维护规则：每个 Issue 交付时，在对应样例条目下追加 `验证结果：通过/失败原因（日期）`；若样例需要替换，需同时更新这里与对应 Issue CSV 的 `refs`。

### 1) Timeline 缩略图缺失（样例：HTML 中有图但 Timeline 无缩略图）
- Feed：dc Rainmaker（https://www.dcrainmaker.com/feed）
- 文章链接/ID：https://www.dcrainmaker.com/2025/12/christmas-tree-by-cargo-bike-2025.html
- 前置条件：Preferences > Timeline 开启缩略图；网络可用
- 操作步骤：进入该文章所在列表 → 观察该行缩略图（滚动触发复用后再观察一次）→ 打开文章确认正文存在 `<img>`（含 `srcset`）
- 期望结果（成功路径）：Timeline 显示非空缩略图，且不会明显拖慢滚动
- 期望结果（失败路径，用于定位缺陷）：若 Timeline 缩略图为空，记录该文章的 `contentHTML/summary/rawImageLink` 以及首个 `<img>` 的 `src/srcset`，用于对照 `Article.imageLink` 兜底逻辑
- 验证结果：NNW-020 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；未能运行 XCTest（签名/测试 target 构建问题），UI 行为需按该样例手工复测

### 2) Hover Translation 重试（样例：失败后按 modifier 重新发起请求）
- Feed：任意（建议同“缩略图样例”文章）
- 文章链接/ID：同上（选择至少 1 段可翻译段落）
- 前置条件：Preferences > AI 启用 Hover Translation；modifier=Control（或用户设置）；可制造失败（例如 provider 配置无效、断网）
- 操作步骤（失败）：鼠标悬停段落并按 modifier → 等待 error → 再次按 modifier
- 期望结果（失败→重试→成功）：第二次按 modifier 进入 loading 并重新发起翻译请求；成功后替换为翻译文本；成功状态下 modifier 仍保持展开/折叠
- 验证结果：NNW-030 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；需按该样例手工验证失败→重试→成功与 success toggle

### 3) 启动后自动刷新开关（样例：开/关控制启动刷新）
- Feed：任意（建议至少包含 1 个需要刷新才能出现的新文章的订阅）
- 文章链接/ID：N/A
- 前置条件：Settings > General 存在“启动后自动刷新”（默认开启）；可观察 refresh/sync 触发（日志或状态变化）
- 操作步骤（关闭路径）：关闭开关 → 彻底退出 App → 冷启动 → 观察是否未触发自动 refresh/sync
- 期望结果（关闭路径）：启动流程不调用 `refreshTimer.timedRefresh` / `ArticleStatusSyncTimer.shared.timedRefresh`
- 操作步骤（开启路径）：开启开关 → 冷启动 → 观察自动 refresh/sync 触发
- 期望结果（开启路径）：行为与历史一致（默认开启）
- 验证结果：NNW-040 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；需手工复测冷启动开/关分别是否触发 timedRefresh

### 4) 图片查看器：点击图片打开/关闭（样例：正文图片 -> viewer）
- Feed：任意含图文章（建议同“缩略图样例”文章）
- 文章链接/ID：同上
- 前置条件：正文存在至少 1 张可点击图片（非 tracking pixel / 非 data: 占位图）
- 操作步骤（成功路径）：点击正文图片 → 进入 viewer（可见 X 按钮）→ 点击 X 或按 Esc 关闭
- 期望结果（成功路径）：viewer 打开/关闭动画流畅；关闭后回到原阅读位置
- 操作步骤（失败路径）：点击正文普通链接
- 期望结果（失败路径）：普通链接仍按原行为打开（不误触发 viewer）
- 验证结果：NNW-050 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；需手工验证点击图片打开/ESC/X 关闭与失败降级（下载失败→浏览器打开）

### 5) 图片加载优化（样例：同 URL 请求合并 + 缓存命中）
- Feed：任意含多图/大图文章（建议同“图片查看器样例”文章）
- 文章链接/ID：同上
- 前置条件：可观察图片请求（日志/断点/可视化）；可清理缓存（Preferences/菜单或删除缓存目录）
- 操作步骤：进入含图列表快速滚动触发多次加载 → 观察同一 URL 是否被合并；返回后再次进入列表 → 观察是否命中缓存更快显示；清理缓存后重复
- 期望结果：并发请求被合并、二次进入明显更快；清理缓存后可重新下载且不造成 UI 卡顿
- 验证结果：NNW-070 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；未能运行 XCTest（签名/测试 target 构建问题），需按该样例手工回归合并/缓存命中与慢网/断网表现

### 6) 自定义快捷键（样例：AI Summary/Translate 自定义 + 冲突处理）
- Feed：任意文章（建议同“Hover Translation 样例”文章）
- 文章链接/ID：同上
- 前置条件：Preferences 提供 AI Summary/AI Translate 快捷键录制；AI 功能可用或有一致的禁用提示
- 操作步骤（自定义）：录制快捷键 → 立即在主窗口触发动作 → 重启后再次触发
- 期望结果（自定义）：设置立即生效且持久化；无自定义时行为与当前一致
- 操作步骤（冲突）：录制一个与现有快捷键冲突的组合
- 期望结果（冲突）：阻止保存或按明确规则处理覆盖，并提供可恢复默认
- 验证结果：NNW-080 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；需手工回归 Preferences 录制/冲突提示/重启持久化与主窗口触发

Phase 2：Fix Timeline 缩略图不显示（里程碑：样例文章缩略图恢复且不引入误判）
- 修改入口：`Article.imageLink` 的兜底提取与合法性判断（避免空字符串/无效 URL 直接返回导致不再 fallback）。
- 兼容“文章内有图”的常见 HTML：支持 `data-src`/`data-original`、`srcset` 的首个 URL、单引号属性、过滤 `data:` 占位图等（优先选择可用的 http(s) URL）。
- 保持现有渲染链路不变：Timeline 继续通过 `TimelineCellData.articleImageURL` -> `ImageDownloader` 加载。
- 验证：Timeline 列表滚动时缩略图可稳定出现、不会造成明显卡顿；至少覆盖 3 种不同 Feed 的样例。
- 回归：确认通知缩略图/其他使用 `imageLink` 的场景不受影响（如有）。

Phase 3：Fix 悬停段落翻译失败后无法重试（里程碑：失败后按 modifier 能再次发起翻译请求）
- 问题定位：当前 JS 逻辑在 node 后已存在 `.ai-translation` 时只做显示/隐藏切换，导致 error 状态也无法重新 `postMessage`。
- 方案：为 `.ai-translation` 增加状态标识（如 `data-ai-translation-state=error/loading/success`），当状态为 `error` 时 modifier 触发应走“重试”而不是 toggle。
- 修改点：`DetailWebViewController.injectHoverListener(...)` 生成的 JS（触发逻辑）与 `showTranslationError(...)`（设置 error 状态/呈现）。
- 验证：失败后按 modifier 可再次进入 loading，再成功时替换为翻译内容；成功后 modifier 仍保持原有“展开/折叠”交互。

Phase 4：Feature「启动后自动刷新」（里程碑：Settings->General 可控，默认行为与历史一致）
- 数据层：在 `AppDefaults` 增加新 key（例如 `refreshOnLaunch`），并在 `registerDefaults()` 中设置默认值（建议默认开启以保持现有“启动即刷新”体验）。
- 逻辑层：在 `AppDelegate` 启动流程中以该开关控制是否调用 `refreshTimer.timedRefresh(nil)` / `ArticleStatusSyncTimer.shared.timedRefresh(nil)`。
- 兼容：与既有隐藏选项 `suppressSyncOnLaunch` 的关系（迁移或明确优先级），避免出现“UI 开了但实际没刷新”的分裂状态。
- UI：在 `Preferences.storyboard` 的 General pane 增加 checkbox，绑定到 `GeneralPreferencesViewController` 读写该设置。
- 验证：冷启动与二次启动均符合开关行为；刷新时机不影响主窗口恢复/首屏交互。

Phase 5：Feature 图片查看器（骨架 + 打通链路）（里程碑：点击正文图片可打开 viewer，并可关闭）
- Web 侧：在 `main_mac.js` 增加 image click 拦截（仅限正文图片），发送 `{src, rect, naturalSize}` 到新的 WebKit message handler（避免与 link hover 冲突）。
- Native 侧：在 `DetailWebViewController` 增加对应 `MessageName` 与 `WKScriptMessageHandler` 分发，把图片 URL 与点击位置转交给新的 `ImageViewer` 组件。
- Viewer 形态：优先用覆盖式（overlay）NSWindow/NSPanel + 背景遮罩（`NSVisualEffectView`/layer-backed），右上角 X、ESC 关闭。
- 光标：Web 侧对可点击图片设置 `cursor: pointer`（“小手”）。
- 验证：打开/关闭动画顺滑且不闪白；点击不同图片均可打开；失败时降级为“在浏览器打开图片 URL”。

Phase 6：Feature 图片查看器交互与性能（里程碑：缩放/拖拽/关闭行为完整且低资源）
- 缩放：overlay 捕获 `scrollWheel`，做连续 zoom（1x~4x，接近 1x 自动回弹）并避免与下层滚动冲突。
- 拖拽：1x 时拖拽任意方向触发交互式 dismiss；>1x 时拖拽转为平移（clamp 到可视范围）。
- 渲染优化：大图加载先做屏幕尺寸 downsample（避免直接解码原图导致内存峰值）；必要时再评估 `CATiledLayer`/分块渲染作为二期优化。
- 动画：统一用 layer-backed + `NSAnimationContext`/`CATransaction`，避免主线程同步解码/布局抖动。
- 验证：大图（>10MB）情况下仍能平滑缩放/拖拽；打开/关闭无明显掉帧；Instruments 观察 CPU/内存峰值在可接受范围。
- 验证结果：NNW-060 受限验收（2025-12-25）— 已验证 `XcodebuildMcp` macOS build；需手工验证滚轮缩放/拖拽关闭/平移与大图（>10MB）性能、Instruments（CPU/内存/泄漏）。

Phase 7：Optimize 缩略图/图片加载速度（里程碑：可感知更快且不放大资源占用）
- 现状梳理：Timeline 缩略图走 `ImageDownloader`（内存 + BinaryDiskCache）；确定“慢”的主要来源（网络并发受限/重复下载/解码阻塞/磁盘 IO）。
- 并发与合并：为同 URL 的并发请求做 coalescing（避免同一图片多次下载）；设置合理并发上限（按 host/全局）。
- 缓存策略：利用 HTTP cache（ETag/Last-Modified）或 `URLCache`（若 `Downloader` 支持）；为 viewer 引入与缩略图共享的缓存通路。
- 预取：在 Timeline 可见行范围内做轻量预取（滚动前后 N 行），但确保可取消、不会抢占交互。
- 验证：相同列表第二次进入显著更快；慢网下不会放大卡顿；缓存可按既有清理策略清除。

Phase 8：Feature 自定义快捷键动作（里程碑：用户可为 AI Summary/Translate 设置快捷键并立即生效）
- 复用现有机制：当前快捷键来自 bundle plist + `KeyboardShortcut`（action selector string）；增加 UserDefaults 覆盖层（不破坏默认 plist）。
- 最小落地：先支持 Global shortcuts 的 AI Summary / AI Translate（`MainWindowController` 已有 `aiSummary:` / `aiTranslate:`）。
- 冲突处理：同一 key 绑定多个 action 时给出提示并阻止保存，或采用“后写覆盖”并可回滚（需在 UI 明确）。
- UI：新增 Preferences pane（或在现有 AI/General 下增加一小节）提供快捷键录制控件与“恢复默认”。
- 验证：重启前后均能生效；与现有 Timeline/Detail/Sidebar shortcuts 不冲突；菜单栏显示（若有）与实际一致。

Phase 9：验证、回归与交付（里程碑：构建通过、核心场景回归通过）
- 构建：使用 `XcodebuildMcp` 验证 macOS target build；按受影响范围运行相关 XCTest（若已有对应测试模块）。
- 手工回归清单：Timeline 缩略图、Hover 翻译（成功/失败/重试）、启动自动刷新开关、图片 viewer 全交互、快捷键自定义与冲突。
- 性能回归：对图片 viewer 与 Timeline 滚动做一次 Instruments 快速检查（确保“丝滑 + 低资源”目标达成）。
- Git：严格按 `DEVELOPMENT_WORKFLOW.md` 选择分支/合并/打 tag（大功能建议 feature branch 分阶段合并）。
- 回滚策略：所有新增大交互建议通过 AppDefaults feature flag 保护，出现问题可快速关闭并回退到“在浏览器打开图片”。

⚠️ 风险与注意事项
- HTML 图片提取误判：过宽的正则可能抓到 tracking pixel/广告图；需要过滤尺寸/协议/常见占位。
- WebKit 注入兼容：JS 注入顺序（`main.js` 调用 `postRenderProcessing()`）与 mac 专用脚本需保持一致，避免影响现有 link hover/scroll handler。
- 图片 viewer 性能：大图解码与缩放容易造成内存尖峰；必须做 downsample，并尽量避免在主线程同步解码。
- 快捷键录制：需要处理系统保留快捷键与输入法冲突；并且要与现有 plist shortcuts 的优先级清晰。
- 启动刷新：启动即刷新可能与窗口恢复/账号初始化存在竞争，需评估延迟触发或在主窗口稳定后触发。

📎 参考
- `Shared/Extensions/ArticleUtilities.swift:73`
- `Mac/MainWindow/Timeline/Cell/TimelineCellData.swift:62`
- `Mac/MainWindow/Timeline/Cell/TimelineTableCellView.swift:319`
- `Shared/Images/ImageDownloader.swift:18`
- `Mac/MainWindow/Detail/DetailViewController.swift:75`
- `Mac/MainWindow/Detail/DetailViewController.swift:368`
- `Mac/MainWindow/Detail/DetailWebViewController.swift:89`
- `Mac/MainWindow/Detail/DetailWebViewController.swift:640`
- `Shared/Article Rendering/main.js:159`
- `Mac/MainWindow/Detail/main_mac.js:22`
- `Mac/AppDelegate.swift:217`
- `Mac/AppDefaults.swift:24`
- `Mac/MainWindow/MainWindowController.swift:552`
- `Mac/MainWindow/Keyboard/MainWindowKeyboardHandler.swift:12`
- `Modules/RSCore/Sources/RSCore/AppKit/Keyboard.swift:33`
- `DEVELOPMENT_WORKFLOW.md:5`
