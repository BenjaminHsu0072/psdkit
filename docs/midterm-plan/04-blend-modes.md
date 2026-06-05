# 子计划 4：三种混合模式

## 目标

支持画板当前需要的三种混合模式：

- `normal`
- `multiply`
- `add`，映射 Photoshop 的 **Linear Dodge (Add)**

三种模式必须同时满足：

- 读取 PSD 时识别正确。
- 写出 PSD 后 Photoshop 显示正确。
- PSDKit 自己的合成预览正确。
- 反复保存不会退化为 `normal`。

## PSD 映射

| 模式 | Photoshop 名称 | PSD blend key | 公开可编辑 |
|------|----------------|---------------|------------|
| `normal` | Normal | `norm` | 是 |
| `multiply` | Multiply | 待 fixture 验证，通常为 `mul ` | 是 |
| `add` | Linear Dodge (Add) | 待 Photoshop fixture 验证，通常为 `lddg` | 是 |
| `passThrough` | Pass Through | 待 fixture 验证，通常为 `pass` | 否，仅限组内部语义 |

实现前必须用 Photoshop 或 psd-tools 生成样本确认 key。文档中不要只依赖记忆值。

## 公开与内部模式边界

中期冻结：

- 像素层公开可创建 / 可编辑模式只有 `normal`、`multiply`、`add`。
- `passThrough` 仅用于读取和写入 Photoshop 组的内部语义。
- 画板 UI 不向普通像素层暴露 `passThrough`。
- 外部 PSD 的像素层如果出现 `passThrough` 或其他未知模式，按未知 blend mode 处理：降级为 `normal`，进入兼容性报告。
- 如果组上出现 PSDKit 暂不支持的 blend mode，中期也降级为组 `normal` 或内部默认组语义，并进入兼容性报告。

## 设计任务

1. 更新 `BlendMode`，将三种模式作为稳定公开 API。
2. 明确未知 blend mode 的行为：降级为 `normal`，进入兼容性报告。
3. 明确 group 的 blend mode 行为：`passThrough` 只作为组内部 PSD 语义，不进入像素层公开 API。
4. 定义 PSDKit 预览合成公式。
5. 定义像素误差容忍范围：建议整数 8-bit 精确，若与 Photoshop 存在舍入差异则记录原因。

## 合成规则

### Normal

按 source-over alpha 合成，并叠加图层 opacity。

### Multiply

建议以 premultiplied 或 straight alpha 明确一种内部公式，并用 fixture 对齐 Photoshop 显示。

颜色通道核心关系：

```text
result = source * destination / 255
```

再按 alpha 与图层 opacity 混合。

### Add / Linear Dodge (Add)

颜色通道核心关系：

```text
result = min(255, source + destination)
```

再按 alpha 与图层 opacity 混合。

具体公式必须在 `CompositeBuilder` 中集中实现，不要分散在 Viewer 或写路径。

## 实施任务

1. 更新 blend mode enum 和 fourCC 映射。
2. 读取 layer record 时保留三种模式。
3. 写 layer record 时写出正确 key。
4. `CompositeBuilder` 支持三种模式。
5. 生成三种模式的 PSD fixture 和 golden RGBA。
6. 更新 Viewer 显示或编辑混合模式的能力。
7. 未知模式进入兼容性报告。

## Fixture 矩阵

| Fixture | 覆盖点 |
|---------|--------|
| `blend-normal` | normal 基准 |
| `blend-multiply` | multiply 读写和预览 |
| `blend-add-linear-dodge` | add / Linear Dodge (Add) 读写和预览 |
| `blend-opacity-multiply` | opacity + multiply |
| `blend-alpha-add` | per-pixel alpha + add |
| `blend-unknown-screen` | 未支持模式降级和报告 |

## 验收步骤

1. 用 Photoshop 创建三种 blend mode 样本，确认 PSDKit 读取后的 `BlendMode` 分别正确。
2. PSDKit 新建三层文档，分别设置 `normal`、`multiply`、`add`，保存后 Photoshop 图层面板显示正确名称。
3. PSDKit 读取自己写出的文件，三种 `BlendMode` 不变。
4. PSDKit 合成预览与 Photoshop 导出的合成 PNG 做像素对比。
5. 图层 opacity 为 128 时，三种模式的预览仍符合 golden。
6. 含未知 blend mode 的 PSD 打开后，对应图层降级为 `normal`，兼容性报告包含 `unsupportedBlendMode`。
7. 含组 `passThrough` 的 PSD 打开后，组结构可保留；普通像素层 API 不暴露 `passThrough` 作为可创建模式。
8. 运行完整 `swift test`，既有 normal 图层行为不回归。

## 测试建议

- `BlendModeTests.testReadsSupportedBlendKeys`
- `BlendModeTests.testWritesLinearDodgeForAdd`
- `BlendModeTests.testUnknownBlendModeReportsWarning`
- `BlendModeTests.testPassThroughIsGroupOnly`
- `CompositeBuilderTests.testMultiplyMatchesGolden`
- `CompositeBuilderTests.testAddMatchesGolden`
- `GoldenWriteTests.testBlendModeRoundTrip`

## 风险

| 风险 | 缓解 |
|------|------|
| Photoshop blend key 记错 | 先生成真实 PSD fixture，再实现映射 |
| 合成公式和 Photoshop 有舍入差异 | 用小尺寸 fixture 定位每个通道差异 |
| group pass-through 影响视觉 | 中期明确 group 语义，必要时不支持复杂 group blend |
| 未知模式被静默写成 normal | 必须接入兼容性报告和测试 |

