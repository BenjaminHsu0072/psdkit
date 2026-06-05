# Swift API 设计（草案）

面向「8-bit RGB(A) 位图图层、无样式编辑」的公开 API。命名遵循 Swift API Design Guidelines，内部模型可与 psd-tools 字段名对应。

---

## 1. 入口类型

```swift
/// 表示一个 PSD 文档（version 1, 8-bit RGB 优先）
public final class PSDDocument {
    public var canvasSize: CGSize { get }
    public var colorMode: ColorMode { get }
    public var layers: LayerNode { get }  // 根组
    public var compatibilityReport: PSDCompatibilityReport { get }  // 本次打开会话；不写入 PSD

    public init(size: CGSize, channels: ChannelMode = .rgba) throws
    public static func load(data: Data) throws -> PSDDocument
    public static func load(url: URL) throws -> PSDDocument
    public func data() throws -> Data
    public func save(to url: URL) throws
}
```

### 错误类型

```swift
public enum PSDError: Error, Sendable {
    case invalidSignature
    case unsupportedVersion(Int)
    case unsupportedBitDepth(Int)
    case unsupportedColorMode(ColorMode)
    case unsupportedCompression(Compression)
    case unsupportedLayerKind(String)
    case corruptStructure(String)
    case io(underlying: Error)
}
```

### 兼容报告（中期 M2）

`PSDDocument.load` 成功后可通过 `compatibilityReport` 查看本次打开的有损变更（不写入 PSD）：

- **丢弃图层**：text / adjustment / smart object（`SoLd`/`PlLd`）等 tagged block 识别的非像素层
- **降级**：不支持的 blend mode → Normal；layer mask / effects 被忽略
- **硬拒绝**（抛出 `PSDError`）：Zip 压缩、16-bit、CMYK、version≠1 等（见 `RejectionTests`）

`PSDCompatibilityReport.hasLossyChanges` 与 `issues` 供宿主 App 展示警告；PSDViewer 映射为 `compatibilityWarningMessage`。

### 支持的 blend mode 子集（中期 M4）

像素层读写支持三种 Photoshop fourCC：

| API | fourCC |
|-----|--------|
| `.normal` | `norm` |
| `.multiply` | `mul ` |
| `.add` | `lddg` |

组层使用 `.passThrough`（`pass`）。其余 blend mode 导入时降级为 Normal 并记入兼容报告。

### 嵌套组（中期 M3）

`GroupLayer` 可嵌套；读路径通过 `lsct`/`lsdk` section divider 构建树。写路径 `writeMode: .semantic` 可重建组结构（见 `GroupWriteTests` / `PersistenceRoundTripTests`）。

---

## 2. 图层模型

```swift
public enum LayerKind: Sendable {
    case pixel
    case group
    case unknown(rawType: String)  // 只读占位，不可创建
}

public protocol LayerProtocol: AnyObject, Identifiable {
    var id: UUID { get }           // 运行时稳定 ID（非文件内索引）
    var name: String { get set }
    var isVisible: Bool { get set }
    var opacity: UInt8 { get set } // 0...255
    var blendMode: BlendMode { get set }
    var frame: CGRect { get set }  // 文档坐标，origin + size
    var kind: LayerKind { get }
    var parent: GroupLayer? { get }
}

public final class PixelLayer: LayerProtocol {
    /// 平面像素：RGBA 8-bit，行主序
    public var pixels: PixelBuffer { get set }
}

public final class GroupLayer: LayerProtocol {
    public var children: [any LayerProtocol] { get }
    public func append(_ layer: any LayerProtocol)
    public func insert(_ layer: any LayerProtocol, at index: Int)
    public func remove(_ layer: any LayerProtocol)
}
```

### 与文件格式的映射

| API | 文件 |
|-----|------|
| `PixelLayer.frame` | LayerRecord top/left/bottom/right |
| `PixelLayer.pixels` | Channel image data (R,G,B,-1) |
| `GroupLayer` | `lsct` section divider 对 |
| `opacity`, `blendMode` | Layer record 字段 |

**图层顺序**：`GroupLayer.children[0]` 为**最底层**，`last` 为最顶层（与 Photoshop 面板一致）。写文件时反转为 PSD 存储顺序。

---

## 3. 像素缓冲

```swift
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public var rgba: Data  // width*height*4

    public init(width: Int, height: Int, rgba: Data) throws
    public func cgImage() throws -> CGImage
    public static func from(cgImage: CGImage) throws -> PixelBuffer
}
```

内部写盘前转为 **planar** 通道；读盘后从 planar 转 `rgba`。

---

## 4. 读写选项

```swift
public struct PSDReadOptions {
    public var passthroughUnknownBlocks: Bool = true
    public var strictMode: Bool = false  // true 时遇非像素层即失败
}

public struct PSDWriteOptions {
    public var compression: Compression = .rle  // .raw | .rle
    public var preserveImageResources: Bool = true
    public var regenerateComposite: Bool = true
}
```

---

## 5. 使用示例

### 读取并导出某层

```swift
let doc = try PSDDocument.load(url: psdURL)
guard let layer = doc.layers.descendants().compactMap({ $0 as? PixelLayer }).first else {
    return
}
let image = try layer.pixels.cgImage()
```

### 新建文档并添加图层

```swift
var doc = try PSDDocument(size: CGSize(width: 800, height: 600))
let buffer = try PixelBuffer.from(cgImage: importedCGImage)
let layer = PixelLayer(name: "Background", frame: CGRect(x: 0, y: 0, width: 800, height: 600), pixels: buffer)
doc.layers.append(layer)
try doc.save(to: outURL)
```

### 删除与重命名

```swift
doc.layers.remove(layer)
layer.name = "Renamed"
try doc.save(to: outURL)
```

---

## 6. 内部 API（`@_spi` 或 `internal`）

供测试与调试，不保证稳定：

```swift
enum PSDKitInternal {
    static func parseLayerSection(_ data: Data) throws -> LayerAndMaskInformation
    static func encodePackBits(_ raw: Data) -> Data
}
```

---

## 7. 与 PhotoshopReader 的差异

| 点 | PhotoshopReader | PSDKit |
|----|-----------------|--------|
| 读写 | 只读 | 读写 |
| 类型 | `struct` 嵌套 | `class` 文档 + 图层树 |
| 像素 | 不合成高层 API | `PixelBuffer` + 合成 |
| 依赖 | DataStream | 内置 BinaryReader |

可参考其 `PhotoshopDocument` 分段类型命名，但公开 API 保持更高层。

---

## 8. Viewer 使用的 API 子集

| 功能 | API |
|------|-----|
| 打开文件 | `PSDDocument.load(url:)` |
| 列表 | `doc.layers` 深度优先遍历 |
| 预览 | `PixelLayer.pixels.cgImage()` |
| 改 opacity | `layer.opacity =` |
| 删层 | `group.remove` |
| 加层 | `PixelLayer` + `append` |
| 保存 | `doc.save(to:)` |
