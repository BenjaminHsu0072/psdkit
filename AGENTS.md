# AGENTS.md

## 项目概览

`psdkit` 当前是一个空仓库，仅包含 `README.md`（标题 `# psdkit`）。尚无应用源码、依赖清单、构建脚本、测试或 CI 配置。

## 开发环境

### 可用工具（Cursor Cloud VM）

| 工具 | 版本/路径 |
|------|-----------|
| Git | 2.43.0 |
| Node.js | v22.x（nvm） |
| npm / pnpm / yarn | 已安装 |
| Python | 3.12.3 |
| pip | 已安装 |

### 常用命令

当前仓库无 lint、test、build 或 dev 脚本。克隆后可直接在 `/workspace` 工作：

```bash
git status
cat README.md
```

当项目添加依赖文件后，请在此节补充对应安装与启动命令（例如 `pnpm install`、`pnpm dev`）。

## Cursor Cloud specific instructions

- **仓库状态**：截至初始设置，仓库仅含 `README.md`，无 `package.json`、`pyproject.toml`、`docker-compose.yml` 等文件，因此无需启动任何服务。
- **更新脚本**：VM 启动时的 update script 为 no-op（`true`），因为当前没有依赖需要刷新。待添加依赖清单后，应更新 update script（例如 `pnpm install` 或 `pip install -r requirements.txt`）。
- **服务**：无 MUST/OPTIONAL 服务；E2E 测试尚不适用。
- **分支**：Cloud Agent 功能分支命名格式为 `cursor/<descriptive-name>-3e84`。
