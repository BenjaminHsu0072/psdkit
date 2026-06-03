# PSDKit 设计文档

Swift PSD 读写库的设计说明与实施记录。实现代码在仓库根目录 `Sources/PSDKit`。

## 文档索引

| 文档 | 说明 |
|------|------|
| [**07-workflow.md**](./07-workflow.md) | **开发工作流（直推 main / 方案 C）** |
| [06-testing.md](./06-testing.md) | TDD、golden、fixture |
| [05-implementation-plan.md](./05-implementation-plan.md) | 分阶段实现与验收 |
| [01-landscape.md](./01-landscape.md) | 跨语言 PSD 生态全景 |
| [01-references.md](./01-references.md) | 实施速查与源文件映射 |
| [02-format-v1.md](./02-format-v1.md) | 首版二进制范围 |
| [03-architecture.md](./03-architecture.md) | 模块划分 |
| [04-api-design.md](./04-api-design.md) | 公开 API 草案 |

## 首版范围（摘要）

- 8 bit/channel，PSD v1，RGB 位图图层
- Raw + PackBits RLE；语义写 + passthrough
- 详见各文档

## 规范

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
