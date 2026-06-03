# 实现计划

> **当前基线：`main`** · 工作流见 [07-workflow.md](./07-workflow.md)（已合并读/写/TDD/语义编码/复合图/Viewer）。

阶段 0：准备

- [x] 调研参考实现（跨语言全景见 01-landscape.md）
- [x] 编写 `docs/` 设计文档
- [x] 添加 `Package.swift` 骨架与空 target
- [x] 添加最小 Fixtures（`Scripts/generate_fixtures.py`）


## 阶段 0.5：测试基础设施（TDD）

- [x] `Scripts/generate_test_fixtures.py` — psd-tools 生成 PSD + manifest + rgba golden
- [x] `GoldenReadTests` / `GoldenWriteTests` / `RejectionTests` / `PackBitsGoldenTests`
- [x] 覆盖矩阵 13 正向 + 4 负向（见 [06-testing.md](./06-testing.md)）
- [x] 增加 `semantic` 写往返 fixture（5 个，见 `SEMANTIC_WRITE_IDS`）

---

## 阶段 1：二进制基础（进行中）

**目标**：读/写 Header + 空 Layer 段 + 空 Image Data。

| 任务 | 验收 |
|------|------|
| [x] `BinaryReader` / `BinaryWriter` | round-trip 26 字节 header |
| [x] `FileHeader` codable | 拒绝非 8BPS / 非 v1 / depth≠8 |
| [x] Color Mode + Resources passthrough | 读入再写出字节一致 |
| [x] `PackBitsCodec` | 与 psd-tools `rle.py` 测试向量一致 |

**参考**：`psd-tools/psd/header.py`, `compression/rle.py`

---

## 阶段 2：读路径（进行中）

**目标**：解析多图层 8-bit RGBA PSD，输出 `PixelBuffer`。

| 任务 | 验收 |
|------|------|
| [x] `LayerRecord` 解析 | 与 psd-tools 解析同一 fixture 的 layer 数、bounds 一致 |
| [x] RLE/Raw 通道解压 | fixture 像素抽样通过 |
| Planar → RGBA | 视觉正确 |
| `LayerTreeBuilder` | 扁平层列表顺序正确 |
| [x] `PSDDocument.load` | 公开 API 可用 |

**参考**：`layer_and_mask.py`, psd_sdk `PsdDecompressRle`

---

## 阶段 3：写路径（进行中）

**目标**：从内存模型写出 Photoshop 可打开的 PSD。

| 任务 | 验收 |
|------|------|
| `LayerRecord` 序列化 | 与阶段 2 往返，元数据一致 |
| Channel image data 写入 | RLE 或 Raw |
| 更新 channel length 字段 | psd-tools `_update_channel_length` 同理 |
| [x] 复合 Image Data | `CompositeBuilder` alpha 合成 |
| [x] `PSDDocument.save` passthrough | 默认 `writeMode: .passthrough` |
| [~] `PSDDocument.save` semantic | `PSDWriter` 重建 Layer/Mask；5 个 golden 通过 |
| [x] 全部 fixture semantic 往返 | 10/13 semantic + 3 passthrough 字节测试 |

**参考**：psd-tools write 路径、ag-psd `writePsdBuffer`

---

## 阶段 3.5：从 0 新建 PSD

| 任务 | 验收 |
|------|------|
| [x] `PSDDocument.create` / `makeSolidLayer` | CreateDocumentTests |
| [x] 空画布导出 | 仅复合图 |
| [x] `LayerRGBAInput` / `makePixelLayer` / `rgbaFileURL` | 管线 RGBA → PSD |
| [x] Viewer Export… | 新建文档可另存为 |

---

## 阶段 4：图层编辑 API

**目标**：增删改图层与属性。

| 任务 | 验收 |
|------|------|
| [x] `appendPixelLayer` / `removePixelLayer` | DocumentEditTests |
| [x] 修改 opacity + `markContentModified` | DocumentEditTests |
| [x] offset fixture 语义往返 | `testLayerOffsetBoundsSemanticRoundTrip` |
| 未知 Tagged Block passthrough | 含 `lfx2` 的 fixture 写后 PS 仍显示样式 |

---

## 阶段 5：PSDViewer

**目标**：人工验证读写。

| 任务 | 验收 |
|------|------|
| [x] 打开/保存 | `Apps/PSDViewer` |
| [x] 图层列表 + 合成预览 | CompositeBuilder |
| [~] 增删改 UI | Viewer：Add/Remove 图层（macOS） |
| [x] 错误提示 | `PSDError.userMessage` + Viewer |

---

## 阶段 6：测试与 CI

| 任务 | 验收 |
|------|------|
| Fixtures + golden hash | `swift test` 全绿 |
| 文档同步 | API 与实现一致 |
| README 快速开始 | 5 行代码可跑通 |

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| Layer extra / tagged blocks 规格歧义 | 以 psd-tools 行为为准；fixture 覆盖 |
| RLE 行表与兼容模式 | 对照 psd_sdk 注释；用 PS 导出文件测 |
| 图层组边界错误 | 首版默认扁平；组功能单独 fixture |
| 写后 PS 报错 | 每阶段用 PS 手动验证清单 |
| Unicode 图层名 | 同时写 `luni` + Pascal 名 |

---

## Photoshop 手动验证清单

1. 新建 RGB 8-bit，3 图层，保存 — PSDKit 读层数=3
2. Viewer 改名、改 opacity — PS 中一致
3. Viewer 删除中间层 — PS 中层消失
4. Viewer 导入 PNG 为新层 — PS 中可见
5. 含图层样式的文件 — 只读打开正常；改像素后样式仍在（passthrough）

---

## 后续版本（非 v1）

- Grayscale / 16-bit
- 图层组完整 CRUD
- 更多 blend modes
- Zip 压缩
- iOS Viewer
- 可选：Swift/C++ 桥接 PhotoshopAPI 作 fuzz 对比
