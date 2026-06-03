# PSDKit

用 Swift 读写 Adobe Photoshop **PSD** 文件的库，附带 macOS 查看器用于验证读写与简单图层编辑。

> **当前状态**：调研与设计阶段。实现尚未开始，请先阅读 [`docs/`](./docs/) 目录。

## 首版范围

- 8 bit / channel
- RGB（RGBA）普通**位图图层**
- 不含图层样式（Layer Effects）的解析与编辑；未知数据**原样透传**
- 标准 `.psd`（非 PSB）

## 文档

| 文档 | 说明 |
|------|------|
| [docs/README.md](./docs/README.md) | 文档索引 |
| [docs/01-references.md](./docs/01-references.md) | 规范与对标参考（psd-tools、psd_sdk、ag-psd、PhotoshopReader 等） |
| [docs/02-format-v1.md](./docs/02-format-v1.md) | 首版相关的 PSD 二进制结构 |
| [docs/03-architecture.md](./docs/03-architecture.md) | 核心库 / Viewer / 测试划分 |
| [docs/04-api-design.md](./docs/04-api-design.md) | 计划中的 Swift API |
| [docs/05-implementation-plan.md](./docs/05-implementation-plan.md) | 分阶段实现与验收 |

## 对标参考（实现时优先打开）

1. **[psd-tools](https://github.com/psd-tools/psd-tools)** — 低层/高层分层与 Python 测试
2. **[psd_sdk](https://github.com/MolecularMatters/psd_sdk)** — RLE 与平面通道算法
3. **[ag-psd](https://github.com/Agamnentzar/ag-psd)** — 读写闭环与 fixture 习惯
4. **[PhotoshopReader](https://github.com/hughbe/PhotoshopReader)** — Swift 只读结构参考

规范：[Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

## 计划中的仓库结构

```
Sources/PSDKit/      # 核心库
Sources/PSDViewer/   # macOS SwiftUI 验证应用
Tests/PSDKitTests/   # 单元与 golden 测试
Tests/Fixtures/      # 测试 PSD
```

## 许可证

待定（实现阶段确定；参考项目多为 MIT / BSD）。
