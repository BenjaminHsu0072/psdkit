# PSDKit 设计文档

本目录为 **Swift PSD 读写库** 的实现前调研与设计说明。实现代码尚未开始，当前阶段目标是：对齐业界成熟实现、收敛首版范围、确定模块划分与验证策略。

## 文档索引

| 文档 | 说明 |
|------|------|
| [01-references.md](./01-references.md) | 规范来源与对标参考实现（含链接与模块映射） |
| [02-format-v1.md](./02-format-v1.md) | 首版支持的 PSD 二进制结构与读写要点 |
| [03-architecture.md](./03-architecture.md) | 仓库结构：核心库 / Viewer / 测试 |
| [04-api-design.md](./04-api-design.md) | 计划中的 Swift 公开 API 与数据模型 |
| [05-implementation-plan.md](./05-implementation-plan.md) | 分阶段实现与验收标准 |

## 首版范围（摘要）

- **位深**：仅 8 bit/channel
- **图层**：仅普通**位图图层**（Pixel Layer），**不含图层样式**（Layer Effects / `lfx2` 等）
- **文件**：标准 `.psd`（version=1），非 PSB
- **色彩**：优先 RGB；Grayscale 可作为第二阶段
- **压缩**：Raw + PackBits RLE（Photoshop 8-bit 默认）
- **图层树**：支持扁平像素层 + 可选图层组（Section Divider），首版 Viewer 以「扁平列表 + 简单分组」为主

## 权威规范

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) — 所有字段定义的最终依据

## 建议的对标实现（优先级）

1. **[psd-tools](https://github.com/psd-tools/psd-tools)**（Python）— 低层结构与高层 API 分离最好，**首选逻辑对标**
2. **[psd_sdk](https://github.com/MolecularMatters/psd_sdk)**（C++）— RLE、平面通道、两段式读取，**首选算法对标**
3. **[ag-psd](https://github.com/Agamnentzar/ag-psd)**（TypeScript）— 读写闭环与测试习惯值得借鉴
4. **[PhotoshopReader](https://github.com/hughbe/PhotoshopReader)**（Swift）— 仅读、结构清晰，**Swift 风格参考**
5. **[PhotoshopAPI](https://github.com/EmilDohne/PhotoshopAPI)**（C++20）— 功能最全，用于边界 case 与回归样本来源
