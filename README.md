# PSDKit

Swift 库：读写 **8-bit RGB(A) 位图图层** PSD 文件（首版）。

## 状态

- [x] 设计文档（[`docs/`](./docs/)）
- [x] 核心读路径：`PSDDocument.load`、图层像素、`PackBits` RLE
- [ ] 完整写编码（当前 `save` 为读入字节透传）
- [ ] macOS Viewer

## 快速开始

```swift
import PSDKit

let doc = try PSDDocument.load(url: URL(fileURLWithPath: "sample.psd"))
for case let layer as PixelLayer in doc.root.children {
    print(layer.name, layer.frame, layer.pixels.rgba.count)
}
```

## 构建与测试

```bash
pip install psd-tools pillow
python3 Scripts/generate_test_fixtures.py
swift build
swift test
```

测试 fixture 由 [Scripts/generate_test_fixtures.py](./Scripts/generate_test_fixtures.py) 生成（`generate_fixtures.py` 为兼容入口；依赖 `psd-tools`）。

## 参考实现

见 [docs/01-landscape.md](./docs/01-landscape.md) 与 [docs/REFERENCES.md](./docs/REFERENCES.md)。

## 文档

| 文档 | 说明 |
|------|------|
| [docs/01-landscape.md](./docs/01-landscape.md) | 跨语言参考全景 |
| [docs/05-implementation-plan.md](./docs/05-implementation-plan.md) | 实现计划与进度 |

测试说明见 [docs/06-testing.md](./docs/06-testing.md)。
