# 测试策略（TDD）

PSDKit 采用 **测试先行**：用 [psd-tools](https://github.com/psd-tools/psd-tools) 生成权威 PSD 与 golden 数据，Swift 测试对照读取/写入行为。

## 快速开始

```bash
pip install psd-tools pillow
python3 Scripts/generate_test_fixtures.py
swift test
```

## 目录结构

```
Tests/PSDKitTests/
├── Fixtures/              # 生成的 .psd（13 个正向 + legacy 别名）
├── Golden/
│   ├── manifest.json      # 元数据期望（头、图层、bbox、opacity…）
│   ├── packbits.json      # PackBits 向量（来自 psd-tools rle）
│   ├── rgba/              # 每层 RGBA8888 参考像素（topil）
│   └── rejections/        # 负向 .psd（非法签名/位深/色彩模式）
├── GoldenReadTests.swift
├── GoldenWriteTests.swift
├── RejectionTests.swift
├── PackBitsGoldenTests.swift
└── PackBitsTests.swift
```

## 覆盖矩阵（正向 fixture）

| ID | 覆盖点 |
|----|--------|
| `single-rle-8x8` | 单层、RLE、全画布 |
| `single-raw-8x8` | 单层、RAW 压缩 |
| `single-rgba-rle-16x16` | RGBA 通道、RLE |
| `canvas-1x1` / `canvas-64x64` | 画布尺寸边界 |
| `two-layers` / `three-layers` | 多层、顺序、opacity、offset |
| `mixed-compression` | 同文件 RAW+RLE |
| `layer-offset-10x10-on-32` | 图层 bounds 偏移 |
| `layer-opacity-50` | opacity=128 |
| `layer-hidden` | 可见性标志 |
| `layer-name-unicode` | Unicode 名（`skip_name_check`，待 luni 解析） |
| `rle-gradient-horizontal` | RLE 渐变条带 |

## 负向 fixture

| ID | 期望 `PSDError` |
|----|-----------------|
| `reject-bad-signature` | `invalidSignature` |
| `reject-version-2` | `unsupportedVersion` |
| `reject-depth-16` | `unsupportedBitDepth` |
| `reject-cmyk` | `unsupportedColorMode` |

内存 patch 负向（不新增 binary fixture）：`RejectionTests.testUnsupportedCompressionThrows` 将 golden PSD 的图层通道或 composite image data 压缩码改为 Zip / 未知值，期望 `unsupportedCompression`。

## 中期（M6）测试入口

| 场景 | 命令 / 套件 |
|------|-------------|
| 全量单元测试 | 仓库根目录 `swift test` |
| 兼容报告 + 拒绝 | `swift test --filter 'CompatibilityReportTests|RejectionTests'` |
| 性能 fixture 工厂 | `swift test --filter PerformanceFixtureFactoryTests` |
| 性能基准 CLI | `swift run -c release PSDKitBenchmark --preset small --warmup 1 --iterations 5 --output Benchmarks/Reports/m6-release-small.json`（三档报告输出 `Benchmarks/Reports/`） |
| Viewer 单元测试 | `cd Apps/PSDViewer && swift test` |

Viewer 侧 `DocumentModelCompatibilityTests` 覆盖打开有损 PSD 时的兼容提示文案（`compatibilityWarningMessage` / `compatibilitySummary`）。

## 测试套件说明

| 套件 | 作用 |
|------|------|
| **GoldenReadTests** | 对照 `manifest.json` + `Golden/rgba/*.rgba` 验证读路径 |
| **GoldenWriteTests** | `passthrough` 字节往返；`semantic` 占位（实现写编码后启用） |
| **RejectionTests** | 非法文件必须抛出对应错误 |
| **CompatibilityReportTests** | 有损导入时 `PSDCompatibilityReport` 警告（mask、effects、text/adjustment/smart object 丢弃、blend mode 降级等） |
| **BlendModeTests** | 支持的三种 pixel blend mode（Normal / Multiply / Add）读写 |
| **LayerTreeBuilderTests** / **LayerTreeTests** | 嵌套 `lsct` 组边界与树构建 |
| **PersistenceRoundTripTests** | 语义写回与 midterm 标准文档往返 |
| **PerformanceFixtureFactoryTests** | 性能基准 fixture 工厂（见 `Benchmarks/`） |
| **PackBitsGoldenTests** | PackBits 与 psd-tools 参考编码一致 |
| **PackBitsTests** | 本地 round-trip |
| **PassthroughTests** | 单文件字节级透传 smoke |

## Golden 像素约定

- 参考像素由 **psd-tools `layer.topil().convert("RGBA")`** 导出，与 Photoshop 显示一致。
- PSDKit 读出的 `PixelLayer.pixels.rgba` 必须与 `Golden/rgba/{fixture}-layer{n}.rgba` **逐字节相等**。
- 后续若调整平面通道合成逻辑，先更新生成脚本再改实现。

## 写路径 TDD 阶段

| 阶段 | `v1_write_roundtrip` | 测试 |
|------|----------------------|------|
| `passthrough`（默认） | `testPassthroughRoundTripBytes` — 原样写回 |
| `semantic` | `testSemanticWriteRebuildsPixels` — 10 个 fixture 像素往返 |

在 `generate_test_fixtures.py` 中为 fixture 设置 `v1_write_roundtrip="semantic"` 即可启用 `GoldenWriteTests.testSemanticWriteRebuildsPixels`。

## 扩展覆盖

新增场景时：

1. 在 `all_specs()` 增加 `DocSpec`
2. 运行 `python3 Scripts/generate_test_fixtures.py`
3. 提交 `Fixtures/`、`Golden/` 变更
4. `swift test` 应绿；若红则按 TDD 修 PSDKit

可选标签见 `manifest.json` 的 `coverage_tags`。

## 参考

- 生成器：`Scripts/generate_test_fixtures.py`
- 参考实现索引：`docs/01-landscape.md`
- 实施备忘：`docs/REFERENCES.md`
