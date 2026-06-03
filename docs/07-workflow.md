# 开发工作流

本文档记录 **PSDKit 仓库的协作与 Agent 交付方式**，与 `AGENTS.md`（速查）互补。

## 方案 C：直推 `main`（当前采用）

适用于本仓库：**小项目、单维护者、快速迭代**。

| 规则 | 说明 |
|------|------|
| 集成分支 | 仅 **`main`** |
| 交付方式 | 本地改代码 → `swift test` 全绿 → **`git push origin main`** |
| Pull Request | **不创建** Draft / 常规 PR，不等待人工 Merge |
| 功能分支 | 可选 `cursor/<描述>-9904` 本地开发，完成后合并进 `main` 再 push |
| Cloud Agent | 任务结束必须 push 到 `main`，不要只留远程分支 |

### 标准命令序列

```bash
git checkout main && git pull origin main
# … 编辑 …
swift build && swift test
git add -A && git commit -m "feat: …"
git push origin main
```

### GitHub 侧前提（维护者一次性配置）

- Cursor GitHub App 已安装且对仓库有 **Contents: Write**
- `main` 分支规则：Cursor App 在 **Bypass list**，或允许直推
- 旧 Draft PR（#2/#4/#5/#6 等）已关闭；历史已合并 PR（#1/#3/#7）可保留记录

### 不再使用的流程

- ~~堆叠 Draft PR（#3 → #4 → #5 → #6）~~
- ~~等用户点击 Merge pull request~~
- ~~仅 push 功能分支而不更新 `main`~~

## 测试与 fixture

```bash
swift test
pip install psd-tools pillow && python3 Scripts/generate_test_fixtures.py  # 再生 golden 时
```

详见 [06-testing.md](./06-testing.md)。

## macOS Viewer

```bash
cd Apps/PSDViewer && swift run PSDViewer
```

## 相关文档

| 文件 | 用途 |
|------|------|
| [AGENTS.md](../AGENTS.md) | Agent / 协作者速查 |
| [README.md](../README.md) | 项目介绍与快速开始 |
| [05-implementation-plan.md](./05-implementation-plan.md) | 功能阶段与进度 |
