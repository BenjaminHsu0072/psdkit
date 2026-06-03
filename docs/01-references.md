# 参考实现与对标说明

## 1. 规范与综述

| 资源 | 用途 |
|------|------|
| [Adobe PSD/PSB Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) | 字段布局、长度块、Unicode 字符串、Tagged Blocks |
| [EGFF: Photoshop PSD Summary](https://www.fileformat.info/format/psd/egff.htm) | 历史格式说明，辅助理解 Layer 区段 |
| [SideFX HDK IMG_FilePSD](https://www.sidefx.com/docs/hdk/_i_m_g___file_p_s_d_8h_source.html) | RLE「兼容模式」与平面数据组织的工程注释 |

> 实现时以 Adobe 官方文档为准；其他资料仅作交叉验证。

---

## 2. Swift 生态现状

| 项目 | 语言 | 读写 | 维护 | 评价 |
|------|------|------|------|------|
| [hughbe/PhotoshopReader](https://github.com/hughbe/PhotoshopReader) | Swift | 只读 | 2021 后基本停更 | **结构映射清晰**，适合照抄 Section 划分与 `DataStream` 模式 |
| [featherJ/psd.swift](https://github.com/featherJ/psd.swift) | Swift | 解析+渲染 | 2016 停更 | 偏展示，不适合作为写路径参考 |
| [EmilDohne/PhotoshopAPI](https://github.com/EmilDohne/PhotoshopAPI) | C++20 | 读写 | 活跃 | 功能完整；可通过 Swift/C++ 互操作作**黑盒回归**，不建议首版直接依赖 |

**结论**：没有成熟的纯 Swift PSD **写**库。PSDKit 应自建写路径，读路径可参考 PhotoshopReader + psd-tools 的分层设计。

### PhotoshopReader 结构（Swift 对标）

其顶层与 Adobe 五段式一一对应，与我们的目标一致：

```swift
// https://github.com/hughbe/PhotoshopReader/blob/master/Sources/PhotoshopReader/PhotoshopDocument.swift
public struct PhotoshopDocument {
    public let header: PhotoshopDocumentHeader
    public let colorModeData: PhotoshopDocumentColorModeData
    public let imageResources: PhotoshopDocumentImageResources
    public let layerAndMaskInformation: PhotoshopDocumentLayerAndMaskInformation
    public let imageData: PhotoshopDocumentImageData
}
```

依赖 [DataStream](https://github.com/hughbe/DataStream) 做 Big-Endian 读取。我们可改用 Swift `Data` + 内部 `BinaryReader`/`BinaryWriter`，避免外部依赖或将其作为可选。

---

## 3. 首选逻辑对标：psd-tools

**仓库**：[psd-tools/psd-tools](https://github.com/psd-tools/psd-tools)  
**文档**：[readthedocs](https://psd-tools.readthedocs.io/)

### 为何选它

- **双层架构**：`psd_tools.psd.*`（二进制）+ `psd_tools.api.*`（文档/图层树）
- Layer 区段注释详尽，与 Adobe spec 一致
- 自带 RLE 纯 Python 实现，便于移植单元测试向量
- 支持图层增删改的 API 设计（`group.append`, `create_pixel_layer`）

### 建议直接对照的源文件

| 模块 | 路径 | PSDKit 对应 |
|------|------|-------------|
| 文件头 | [`psd/header.py`](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/psd/header.py) | `FileHeader` |
| 图层与蒙版 | [`psd/layer_and_mask.py`](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/psd/layer_and_mask.py) | `LayerRecord`, `ChannelData` |
| RLE | [`compression/rle.py`](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/compression/rle.py) | `PackBitsCodec` |
| 高层 API | [`api/psd_image.py`](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/api/psd_image.py) | `PSDDocument` |
| 图层类型 | [`api/layers.py`](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/api/layers.py) | `PixelLayer`, `Group` |

### 文件头格式（与实现对齐）

psd-tools 使用的 struct 格式（Big-Endian）：

```
4sH6xHIIHH  →  signature, version, (reserved), channels, height, width, depth, color_mode
```

对应 Swift：

```swift
// 26 bytes fixed
// signature: "8BPS", version: 1, reserved: 6 zero bytes
```

### 图层记录核心字段

来自 `LayerRecord`（[`layer_and_mask.py`](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/psd/layer_and_mask.py)）：

| 字段 | 类型 | 说明 |
|------|------|------|
| top, left, bottom, right | Int32 ×4 | 图层 bounds（bottom/right 为开区间边界） |
| channel_info | List | 通道 ID + 数据长度 |
| signature | "8BIM" | 固定 |
| blend_mode | 4-char key | 首版可固定 `norm` |
| opacity | UInt8 | 0–255 |
| clipping | UInt8 | 0=base, 1=non-base |
| flags | UInt8 | visible 等为位标志 |
| extra | variable | mask, blending ranges, Pascal name, tagged blocks |

**图层顺序**：文件中从「最上层」到「最底层」存储（与 Photoshop 面板自上而下相反）。psd-tools 在 API 层会反转以符合 UI 直觉。

**分组**：扁平 `LayerRecord` 列表 + `SectionDivider` / `lsct` Tagged Block 标记组边界。首版可实现「读组 + 写简单组」，Viewer 用缩进展示即可。

---

## 4. 首选算法对标：psd_sdk (Molecular Matters)

**仓库**：[MolecularMatters/psd_sdk](https://github.com/MolecularMatters/psd_sdk)（~650⭐，BSD-2-Clause）

### 模块划分（CMake 源文件分组）

| 分组 | 代表文件 | 说明 |
|------|----------|------|
| Parser | `PsdParseLayerSection.*`, `PsdParseImageDataSection.*` | 按 Section 解析 |
| ImageUtil | `PsdDecompressRle.*`, `PsdInterleave.*` | RLE + 平面↔交错 |
| Exporter | `PsdExportLayer.*`, `PsdExportDocument.*` | 写 PSD |
| Util | `PsdEndianConversion.*`, `PsdSyncFileReader.*` | 字节序与 I/O |

### 两段式读取（可借鉴）

1. **Parse**：快速扫描，构建 layer/channel 元数据与文件内偏移
2. **Extract**：按通道并行解压像素（无 seek 的流式读取）

Swift 可用 `async`/`TaskGroup` 在 Extract 阶段并行解压各 channel。

### RLE

Photoshop 8-bit 使用 **Apple PackBits**，与 psd-tools 的 `encode`/`decode` 语义一致。移植时建议：

1. 从 psd-tools 复制若干 round-trip 测试向量
2. 与 psd_sdk 的 `PsdDecompressRle` 对同一 fixture 比对（若引入 C++ 测试 harness）

---

## 5. 读写闭环参考：ag-psd

**仓库**：[Agamnentzar/ag-psd](https://github.com/Agamnentzar/ag-psd)（TypeScript，~650⭐）

### 可借鉴点

- `readPsd` / `writePsdBuffer` 单一入口
- 明确声明：**不根据图层属性重绘位图**（与我们的首版范围一致）
- 测试 PSD fixture 丰富（`test/psd/`, `test/write/`）

### 需注意

- 默认处理大量 Tagged Blocks；首版应 **原样透传** 未知 block，避免破坏 Photoshop 可打开性
- 文本/矢量层依赖 `invalidateTextLayers` 等技巧 — **首版不支持**

---

## 6. 全功能参考：PhotoshopAPI

**仓库**：[EmilDohne/PhotoshopAPI](https://github.com/EmilDohne/PhotoshopAPI)  
**文档**：[photoshopapi.readthedocs.io](https://photoshopapi.readthedocs.io/)

基于 psd_sdk、pytoshop、psd-tools 演进，支持 8/16/32 bit、效果、智能对象等。

**用途**：

- 生成「复杂 PSD」作为**负向测试**（首版应明确报错或只读元数据）
- 长期扩展时的 API 形状参考（`LayeredFile`, `ImageLayer` 等概念）

**不建议首版依赖**：C++20 构建链、许可证与二进制体积对 Swift Package 不友好。

---

## 7. 参考代码映射表（实现 checklist）

实现某功能前，建议按此表打开对照仓库：

| 功能 | 主参考 | 备参考 |
|------|--------|--------|
| File Header 读写 | psd-tools `header.py` | PhotoshopReader `PhotoshopDocumentHeader` |
| Color Mode Data | psd-tools `color_mode_data.py` | ag-psd `readColorModeData` |
| Image Resources | psd-tools `image_resources.py` | 首版：透传 |
| Layer Info 解析 | psd-tools `layer_and_mask.py` | psd_sdk `PsdParseLayerSection` |
| PackBits RLE | psd-tools `compression/rle.py` | psd_sdk `PsdDecompressRle` |
| 平面→RGBA 交错 | psd_sdk `PsdInterleave` | psd-tools `api/layers.py` composite |
| 写 Layer 记录 | psd-tools write 路径 | ag-psd `writePsd` |
| 图层树重建 | psd-tools `api/layers.py` | ag-psd `children` |
| 合并预览图 | psd-tools composite | Viewer 用 Core Graphics 自行合成 |

---

## 8. 测试与 Fixture 策略

| 来源 | 内容 |
|------|------|
| 自建 | `Tests/Fixtures/`：最小 1×1、多图层、RLE/Raw、透明通道 |
| ag-psd | 简单 RGB 多图层（注意许可证 MIT） |
| psd-tools | 可用 Python 脚本生成 golden 文件，Swift 测试读入比对 hash |
| 手工 | Photoshop 导出「无样式位图图层」8-bit RGB PSD |

**回归原则**：

1. **Round-trip**：`read → modify name/opacity → write → read` 字段一致
2. **像素**：解压后 `SHA256` 与 golden 一致
3. **Photoshop 打开**：Viewer 导出文件需在 PS 中无损坏提示（人工抽查清单）

---

## 9. 许可证注意

| 项目 | 许可证 | 抄代码 |
|------|--------|--------|
| psd-tools | MIT | 可移植算法与测试思路，注明出处 |
| psd_sdk | BSD-2-Clause | 可参考，勿大段复制 |
| ag-psd | MIT | 测试 fixture 需看仓库 LICENSE |
| PhotoshopReader | 需查看 repo | 结构可参考，逐文件核对 |

实现时：**以规范重写**，参考仓库用于对照与测试向量，避免盲目粘贴。
