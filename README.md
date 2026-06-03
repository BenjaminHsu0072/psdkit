# PSDKit

Swift 库：读写 **8-bit RGB(A) 位图图层** PSD 文件（首版）。

## 状态（`main`）

| 能力 | 说明 |
|------|------|
| 读路径 | `PSDDocument.load`、RLE/RAW 通道、多层 RGBA |
| 写路径 | 默认 **passthrough**；`writeMode: .semantic` 重建图层与复合图 |
| 图层编辑 | `appendPixelLayer` / `removePixelLayer`、`markContentModified()` |
| Unicode 名 | `luni` 解析与写入 |
| 测试 | 20 项 golden / TDD（见 [docs/06-testing.md](./docs/06-testing.md)） |
| Viewer | macOS [`Apps/PSDViewer`](./Apps/PSDViewer/) |

## 快速开始

```swift
import PSDKit

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

## 文档

| 文档 | 说明 |
|------|------|
| [docs/README.md](./docs/README.md) | 文档索引 |
| [docs/05-implementation-plan.md](./docs/05-implementation-plan.md) | 实现计划 |
| [docs/06-testing.md](./docs/06-testing.md) | 测试与 TDD |

## 开发分支说明

历史 PR 分支（`cursor/psdkit-*-9904`）已 **fast-forward 合并入 `main`**。后续开发请从 `main` 拉取：

```bash
git checkout main && git pull
git checkout -b cursor/<feature>-9904
```
