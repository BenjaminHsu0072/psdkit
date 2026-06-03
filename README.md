# PSDKit

Swift 库：读写 **8-bit RGB(A) 位图图层** PSD 文件（首版）。

## 状态（`main`）

| 能力 | 说明 |
|------|------|
| 读路径 | `PSDDocument.load`、RLE/RAW 通道、多层 RGBA |
| 写路径 | 默认 **passthrough**；`writeMode: .semantic` 重建图层与复合图 |
| 从 0 新建 | `PSDDocument.create`、`makePixelLayer`、`LayerRGBAInput` |
| 图层编辑 | `appendPixelLayer` / `removePixelLayer`、`markContentModified()` |
| Unicode 名 | `luni` 解析与写入 |
| 测试 | golden / TDD（`swift test`，见 [docs/06-testing.md](./docs/06-testing.md)） |
| Viewer | macOS [`Apps/PSDViewer`](./Apps/PSDViewer/) — New / Open / Save / Export |

## 快速开始

```swift
import PSDKit

// 从空白新建并导出
let size = PSDSize(width: 256, height: 256)
let layer = try PSDDocument.makeSolidLayer(name: "Export", canvasSize: size, red: 255, green: 0, blue: 0)
var doc = try PSDDocument.create(canvasSize: size, layers: [layer])
try doc.save(to: URL(fileURLWithPath: "out.psd"))

// 由管线生成的图层 RGBA 文件组装 PSD
let spriteURL = URL(fileURLWithPath: "layers/sprite.rgba")  // 原始 RGBA8888
let sprite = try PSDDocument.makePixelLayer(
    name: "Sprite",
    frame: PSDRect(left: 10, top: 20, right: 74, bottom: 84),
    rgbaFileURL: spriteURL
)
let bg = try PSDDocument.makeSolidLayer(name: "BG", canvasSize: size, red: 255, green: 255, blue: 255)
doc = try PSDDocument.create(canvasSize: size, layers: [bg, sprite])

// 或一次性传入内存中的图层缓冲
let exported: [LayerRGBAInput] = [
    LayerRGBAInput(name: "BG", left: 0, top: 0, width: 256, height: 256, rgba: bgData),
    LayerRGBAInput(name: "FG", left: 0, top: 0, width: 64, height: 64, rgba: fgData),
]
doc = try PSDDocument.create(width: 256, height: 256, exportedLayers: exported)
try doc.save(to: URL(fileURLWithPath: "composed.psd"))

// 打开已有文件
let doc = try PSDDocument.load(url: URL(fileURLWithPath: "sample.psd"))
for case let layer as PixelLayer in doc.root.children {
    print(layer.name, layer.frame, layer.pixels.rgba.count)
}

// 编辑后语义写回
layer.opacity = 200
doc.markContentModified()
try doc.save(to: outURL)  // 未 mark 时默认 passthrough 原字节
```

## 构建与测试

```bash
swift build
swift test
```

再生 golden fixture（需 Python）：

```bash
pip install psd-tools pillow
python3 Scripts/generate_test_fixtures.py
```

## macOS Viewer

```bash
cd Apps/PSDViewer && swift run PSDViewer
```

新建文档后使用 **Export…** 或 **Save**（无路径时自动弹出保存面板）导出 PSD。

## 文档

| 文档 | 说明 |
|------|------|
| [docs/README.md](./docs/README.md) | 文档索引 |
| [docs/05-implementation-plan.md](./docs/05-implementation-plan.md) | 实现计划 |
| [docs/06-testing.md](./docs/06-testing.md) | 测试与 TDD |

## 开发流程

默认 **直推 `main`**（`swift test` 通过后即 push，不开 Draft PR）。

```bash
git checkout main && git pull
# … 修改 …
swift test && git push origin main
```
