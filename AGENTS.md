# AGENTS 全局配置 (NetNewsWire 定制版)

> 版本: 3.6-NetNewsWire
> 适配环境: macOS 15.6, Xcode, Swift/Obj-C
> 说明: Codex CLI 全局指令，集成 XcodebuildMcp

---

## 🎯 设计目标
为 NetNewsWire 项目提供自动化开发代理。聚焦 macOS 原生体验（Silky Smooth），严格遵守 Xcode 工程规范。

## 📊 优先级栈
1. **编译与运行**：必须保证 `XcodebuildMcp` 构建通过，任何代码修改不得破坏构建。
2. **原生体验**：UI/UX 必须符合 macOS Human Interface Guidelines (特别是动画流畅度)。
3. **上下文与持久性**：严格遵守 Plan 和 Issue 边界。
4. **质量标准**：Swift/Obj-C 混编安全性，内存管理（ARC）。

---

## 🛠️ 工具约定 (NetNewsWire 特化)

### Xcode 与 构建 (XcodebuildMcp)
- **构建优先**：在 `Verification` 阶段，必须调用 `XcodebuildMcp` 验证构建。
- **测试**：优先运行受影响模块的 XCTest。
- **环境**：当前环境为 macOS 15.6。

### Git 工作流
- **提交策略**：严格遵守 `DEVELOPMENT_WORKFLOW.md`。
- **Push 时机**：
  - 当 `issues_csv_execute` 中一个 Issue 达到 `git_state: 已提交` 且构建通过时，检查是否满足 Push 条件。
  - 若满足，执行 Push 并附带清晰的 Commit Message。

---

## 🔄 工作流程 (通用)

### 1. 接收与现实检查
- 确认 NetNewsWire 的 target 设置。
- 确认 Swift 版本兼容性。

### 2. 上下文收集
- 搜索 feeds 解析逻辑 (针对 "少数派" 缩略图问题)。
- 搜索 `NSTextView` 或自定义渲染逻辑 (针对翻译悬停问题)。
- 搜索 `NSImage` / `NSScrollView` 相关逻辑 (针对图片查看器)。

... (保留原版 AGENTS.md 中 "规划"、"执行"、"验证"、"交接" 等通用部分，此处省略以节省篇幅，请复制你提供的原版 AGENTS.md 的剩余部分拼接在此处) ...
