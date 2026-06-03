# PSD 格式要点（首版 8-bit 位图图层）

本文档提炼 [Adobe 规范](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) 中与 **PSDKit v1** 相关的部分。未列出的特性首版可**原样保留字节**（passthrough）或**拒绝写入**。

---

## 1. 文件整体结构

```
┌─────────────────────────────────────┐
│ File Header          (26 bytes)     │  固定长度
├─────────────────────────────────────┤
│ Color Mode Data      (4 + N)        │  长度前缀
├─────────────────────────────────────┤
│ Image Resources      (4 + N)        │  长度前缀
├─────────────────────────────────────┤
│ Layer & Mask Info    (4 + N)        │  长度前缀 ← 核心
├─────────────────────────────────────┤
│ Image Data           (2 + data)     │  合并后的复合图
└─────────────────────────────────────┘
```

- 所有多字节整数：**Big-Endian**
- 长度块：先读 `UInt32` length，再读 payload；写时回填 length
- 多数区段末尾 **padding 到 2 或 4 字节边界**

---

## 2. File Header（26 bytes）

| 偏移 | 大小 | 字段 | v1 约束 |
|------|------|------|---------|
| 0 | 4 | Signature `8BPS` | 必须 |
| 4 | 2 | Version | **1**（非 PSB） |
| 6 | 6 | Reserved | 0 |
| 12 | 2 | Channels | 3–4（RGB 或 RGB+alpha） |
| 14 | 4 | Height | 1…300000 |
| 18 | 4 | Width | 1…300000 |
| 22 | 2 | Depth | **8** |
| 24 | 2 | Color Mode | **3 = RGB**（首版） |

**拒绝条件**（读时 `throw` / 写时 precondition）：

- `version != 1`
- `depth != 8`
- `color_mode` 非 RGB（首版）
- Signature 非 `8BPS`

---

## 3. Color Mode Data

| 字段 | 说明 |
|------|------|
| Length | UInt32，RGB 通常为 **0** |
| Data | 索引色/双色调等；RGB 为空 |

v1：**读写过零长度**；若 length > 0 则读入 `Data` 原样保存以便 round-trip。

---

## 4. Image Resources

结构：重复 `(type, name, data)` 直到块结束。

v1 策略：

- **读**：解析已知 ID（如 thumbnail `0x0409`）可选；未知 ID **整段保留**
- **写**：未修改则原样写回；新建文件可只写最小集（如兼容模式 composite `0x040D` 可选）

首版 Viewer 不依赖 Resources；写路径至少保证 Photoshop 能打开（可参考 ag-psd 默认写入项）。

---

## 5. Layer and Mask Information

```
LayerAndMaskInformation
├── length: UInt32
└── body
    ├── LayerInfo (optional)
    │   ├── length: UInt32
    │   ├── layer_count: Int16  （负数表示合并透明通道特殊语义）
    │   ├── layer_records[]
    │   └── channel_image_data[]  （与 records 一一对应）
    ├── GlobalLayerMaskInfo (optional)
    └── tagged_blocks (optional, document-level)
```

### 5.1 Layer Record（元数据）

顺序（与 psd-tools `LayerRecord.read` 一致）：

1. `Int32 top, left, bottom, right`
2. `UInt16 num_channels`
3. `num_channels × ChannelInfo` — `(Int16 id, UInt32 length)`
4. `4s signature` = `8BIM`
5. `4s blend_mode` — 首版默认 `norm`
6. `UInt8 opacity`
7. `UInt8 clipping`
8. `LayerFlags` (1 byte)
9. **Extra data**（length-prefixed）：
   - Mask data（v1：可为空，length=0）
   - Layer blending ranges（可写默认）
   - Layer name（Pascal string, MacRoman 或 UTF-8 由 tagged block 补充）
   - **Additional Layer Information** (Tagged Blocks)

### 5.2 Channel ID

| ID | 含义 |
|----|------|
| 0, 1, 2 | R, G, B |
| -1 | 透明度蒙版（用户通道） |
| -2, -3 | 图层蒙版相关（v1 可无） |

RGB 位图图层典型：**4 通道**（R,G,B,Alpha）或 **3 通道**（无透明）。

### 5.3 Channel Image Data

每个通道：

```
UInt16 compression   // 0=Raw, 1=RLE
bytes data
```

- **Raw**：`width × height` 字节
- **RLE**（8-bit 常用）：
  - 先 `height × 2` 字节的**行字节长度表**（兼容模式）
  - 再 PackBits 压缩数据

平面存储：每个通道一整块，**非交错 RGB**。

解码后需 **interleave** 为 RGBA 供 SwiftUI/CoreGraphics 显示：

```
[R plane][G plane][B plane][A plane]  →  RGBA8888
```

参考：psd_sdk `PsdInterleave`，psd-tools `numpy` channel 合并。

### 5.4 图层顺序与合成

- 文件内 layer_records：**从上到下**（先画的在上）
- UI 展示常 **反转** 为从底到顶
- 合并预览：按 opacity + blend mode 叠合；v1 仅支持 **normal** blend，可忽略高级混合

### 5.5 图层组（可选 v1.1）

Tagged Block key `lsct` / Section Divider：

- `bound` — 组开始（标题层）
- `openFolder` / `closedFolder` — 组结束

首版读：可解析为树；写：可只支持**扁平列表**（无组）或**单层组**。

---

## 6. Image Data Section（复合图）

```
UInt16 compression
channel data...  // 与文档 channel 数一致，平面存储
```

启用 **Maximize Compatibility** 的 PSD 在 Layer 段之后仍有完整复合图。

v1：

- **读**：解压用于缩略图/预览
- **写**：在修改图层后**重新合成**写入，或从图层栈渲染（Viewer 责任）

---

## 7. 首版明确不支持（读时可跳过 / 写时拒绝）

| 特性 | 标识 / 说明 |
|------|-------------|
| PSB (large doc) | version=2, 64-bit lengths |
| 16 / 32 bit | depth ≠ 8 |
| 图层样式 | Tagged `lfx2`, `lrFX`, effects layers |
| 调整图层 | Levels, Curves, … |
| 文字图层 | `TySh`, `Txt ` |
| 矢量 / 形状 | `vmsk`, `vogk` |
| 智能对象 | `PlLd`, `SoLd` |
| CMYK / Lab / Indexed | color_mode ≠ RGB |
| Zip 预测压缩 | compression=2,3（首版仅 0,1） |

**策略**：

- 读取含上述特性的文件：若存在**可解码的像素层**，则读取像素 + **保留未知 tagged blocks 字节**；否则整体报错并说明原因
- 写入：仅生成「纯像素层 + 最小 tagged blocks」的文件

---

## 8. 位图图层判定（v1）

满足以下条件视为 **v1 兼容像素层**：

1. 存在 R/G/B 通道像素数据（length > 2）
2. 无 `TySh`（文字）、无 `SoLd`（智能对象）等「非像素」主类型 block
3. 不依赖 `lfx2` 渲染才能看见内容（即：像素数据即所见）

**图层样式**：即使文件含 `lfx2`，若用户仅编辑像素/名称/可见性，写回时应 **原样保留 `lfx2` 字节**（passthrough），不在 Swift 侧解析效果。

---

## 9. Unicode 图层名

- Legacy：Extra 内 Pascal string（MacRoman）
- 现代：`luni` tagged block（UTF-16 BE）

读写时优先 `luni`；写时两者可同步更新以避免 PS 显示旧名。

---

## 10. 最小合法 PSD 写入清单

新建 100×100 RGBA 文档、单图层：

1. Header: 4 channels, RGB, depth 8
2. Color mode length = 0
3. Image resources: 空或最小
4. Layer info: layer_count=1, 1 record, 4 channels RLE/Raw
5. Channel image data for R,G,B,-1
6. Image data: 合成图 RLE

用 Photoshop 打开验证无「修复文档」对话框。
