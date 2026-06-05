# 子计划 2：兼容性报告

## 目标

打开 PSD 时不拆分 Open / Import 两套入口，而是在统一读取流程中生成兼容性报告：

- 支持子集内的内容正常进入可编辑模型。
- 不支持但可降级的内容进入报告，并按规则处理。
- 无法安全读取的内容返回明确错误。

兼容性报告的目标不是阻止用户打开文件，而是避免静默丢失信息。

## 冻结 API

```swift
public struct PSDCompatibilityReport: Sendable {
    public var issues: [PSDCompatibilityIssue]
    public var hasLossyChanges: Bool
}

public struct PSDCompatibilityIssue: Sendable {
    public enum Severity: Sendable {
        case info
        case warning
        case error
    }

    public enum Kind: Sendable {
        case unsupportedLayerKind
        case unsupportedBlendMode
        case unsupportedMask
        case unsupportedLayerEffect
        case unsupportedCompression  // 未来扩展保留；中期 Zip / ZipPrediction 硬拒绝，不生成 report issue。
        case droppedLayer
        case rasterizedOrFlattenedContent
    }

    public var severity: Severity
    public var kind: Kind
    public var layerName: String?
    public var message: String
}
```

M2 冻结点：报告挂载在 `PSDDocument` 上，读取成功后通过 `document.compatibilityReport` 获取。

```swift
public final class PSDDocument {
    public var compatibilityReport: PSDCompatibilityReport { get }
}
```

冻结要求：

- `PSDDocument.load(data:)` 和 `PSDDocument.load(url:)` 成功返回后，报告必须可读取。
- 完全处于支持子集内的 PSD 返回空报告。
- 文件级硬拒绝场景直接抛错，不返回 `PSDDocument`，因此不生成报告。
- 报告只存在于本次打开会话中，不写入 PSD。
- Viewer 或上层画板通过同一 API 展示提示。
- 测试通过稳定 `Kind` 和 `Severity` 断言报告内容。

## 设计任务

1. 实现并冻结 `PSDDocument.compatibilityReport`。
2. 确定 warning 与 error 的边界。
3. 为每类不支持特性定义稳定 `Kind`。
4. 为用户提示准备短文案，不暴露过多 PSD 内部术语。
5. 确认报告不参与保存，只在本次打开会话中存在。

## 实施任务

1. 新增 `PSDCompatibilityReport` 与 `PSDCompatibilityIssue`。
2. 在 `DocumentBuilder` 或读取转换层收集不支持项。
3. 在解析 layer record、tagged blocks、blend mode、compression 时生成 issue。
4. 在 Viewer 打开文件后展示简要提示。
5. 为报告增加单元测试。

## 唯一行为矩阵

| 情况 | 行为 | Issue kind | Severity | `hasLossyChanges` |
|------|------|------------|----------|-------------------|
| 支持子集内 PSD | 正常打开 | 无 | 无 | `false` |
| 未支持混合模式 | 图层导入为 `normal` | `unsupportedBlendMode` | warning | `true` |
| 图层样式 | 忽略样式，保留像素层 | `unsupportedLayerEffect` | warning | `true` |
| 图层蒙版 | 忽略蒙版，保留图层像素 | `unsupportedMask` | warning | `true` |
| 文字层 | 丢弃为可编辑图层 | `unsupportedLayerKind` + `droppedLayer` | warning | `true` |
| 调整层 | 丢弃为可编辑图层 | `unsupportedLayerKind` + `droppedLayer` | warning | `true` |
| 智能对象 | 丢弃为可编辑图层 | `unsupportedLayerKind` + `droppedLayer` | warning | `true` |
| Zip / ZipPrediction 压缩 | 拒绝打开 | 不生成报告 | error | 不适用 |
| 不支持位深/色彩模式 | 拒绝打开 | 不生成报告 | error | 不适用 |

## 验收步骤

1. 打开一个完全处于支持子集内的 PSD，报告为空，`hasLossyChanges == false`。
2. 打开含 `screen` 或其他未支持 blend mode 的 PSD，报告包含 `unsupportedBlendMode`，图层降级为 `normal`。
3. 打开含图层样式的 PSD，报告包含 `unsupportedLayerEffect`，位图层仍可读取。
4. 打开含蒙版的 PSD，报告包含 `unsupportedMask`，中期合成结果符合当前降级规则。
5. 打开含 Zip / ZipPrediction 压缩的 PSD，读取失败并返回明确错误，不产生“跳过图层后成功”的文档。
6. 打开含 16-bit 或 CMYK 的 PSD，读取失败并返回现有明确错误，不产生“假成功”文档。
7. Viewer 打开含 warning 的 PSD 时，用户能看到“部分特性不受支持，已降级”的提示。
8. 保存降级后的 PSD 前，上层可以知道 `hasLossyChanges == true`。

## 测试建议

- `CompatibilityReportTests.testSupportedSubsetHasEmptyReport`
- `CompatibilityReportTests.testUnsupportedBlendModeReportsWarning`
- `CompatibilityReportTests.testLayerEffectsReportWarning`
- `CompatibilityReportTests.testMaskReportsWarning`
- `CompatibilityReportTests.testUnsupportedCompressionThrows`
- `CompatibilityReportTests.testUnsupportedModeStillThrows`

## 风险

| 风险 | 缓解 |
|------|------|
| 报告太细，用户看不懂 | API 保留结构化信息，UI 只展示摘要 |
| 报告太粗，测试不可断言 | 每类问题必须有稳定 `Kind` |
| 打开后保存导致用户误以为无损 | 保存前可通过 `hasLossyChanges` 提醒 |

