# PSDViewer

macOS SwiftUI 应用，用于人工验证 PSDKit 读写。

## 要求

- macOS 13+
- Xcode 15+ 或 Swift 5.9+

## 构建与运行

```bash
cd Apps/PSDViewer
swift build
swift run PSDViewer
```

或在 Xcode 中打开 `Apps/PSDViewer/Package.swift` 作为根包运行。

## 功能

- 打开 / 保存 PSD（8-bit RGB 位图图层）
- 图层列表与可见性切换
- 合成预览（与 `CompositeBuilder` 一致）
