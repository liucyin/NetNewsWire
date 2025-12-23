# NetNewsWire Fork Development Workflow

This guide explains how to manage your code, develop new features, and build releases efficiently using the configured workflow.

## 1. Branching Strategy (分支策略)

*   **`main` Branch**: Consider this your "Stable" or "Production" version. It should always contain working code.
*   **Feature Branches**: Use these for new features or experiments (e.g., `feature/ai-improvements`, `fix/timeline-spacing`). This keeps `main` clean while you work.

## 2. Common Scenarios (常见场景的操作流程)

### Scenario A: Fixing a small bug (e.g., Timeline layout tweak)
For small, quick fixes, you can work directly on `main` or a quick branch.

1.  **Modify code** locally.
2.  **Commit**: `git commit -am "Fix timeline spacing bug"`
3.  **Push**: `git push origin main`
    *   *Note: This usually will NOT trigger a DMG build, saving resources.*

### Scenario B: Developing a Big Feature (e.g., New AI Capability)
1.  **Create a branch**: `git checkout -b feature/new-ai-function`
2.  **Work & Commit**: Make multiple commits as you work.
    *   `git commit -am "Add API logic"`
    *   `git commit -am "Update UI"`
3.  **Merge to Main** (When finished):
    ```bash
    git checkout main
    git merge feature/new-ai-function
    git push origin main
    ```

## 3. How to Build & Release (如何构建安装包)

We have configured GitHub Actions to **NOT** build on every push (to save resources). You have two ways to trigger a build:

### Method 1: Release via Tag (Recommended for Versions)
When you are happy with `main` and want to generate an installer for yourself or others:

1.  **Tag the version** (e.g., v1.1, v1.2):
    ```bash
    git tag v1.1
    ```
2.  **Push the tag**:
    ```bash
    git push origin v1.1
    ```
    *   *Result*: GitHub will automatically build the DMG. You can download it from the "Actions" tab -> "Artifacts".

### Method 2: Manual Trigger (For Testing)
If you just want to test a build without making a new version number:

1.  Go to your GitHub Repository page.
2.  Click **Actions** tab.
3.  Select **Build NetNewsWire DMG** on the left.
4.  Click **Run workflow** -> Select Branch (usually `main`) -> **Run workflow**.

## Summary Cheat Sheet

| Goal | Command / Action |
| :--- | :--- |
| **Start new work** | `git checkout -b feature/name` |
| **Save progress** | `git commit -am "Message"` |
| **Sync to Server** | `git push origin feature/name` (or `main`) |
| **Finish Feature** | `git checkout main` -> `git merge feature/name` -> `git push` |
| **Build Installer** | `git tag v1.X` -> `git push origin v1.X` |

---
**Tip**: If the downloaded DMG says "Damaged" or "Cannot be opened", it is because it is unsigned. Right-click the App icon -> Open -> Open to bypass this.
