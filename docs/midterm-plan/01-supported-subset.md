# 子计划 1：支持子集与降级规则

## 目标

定义 PSDKit 中期可持久化的标准 PSD 子集，并明确外部 PSD 遇到不支持特性时的处理方式。

该文档是后续图层树、混合模式、兼容性报告、往返测试的共同依据。

## 支持范围

| 能力 | 中期支持 |
|------|----------|
| 文件格式 | PSD v1 |
| 位深 | 8 bit/channel |
| 色彩模式 | RGB |
| 图层类型 | 位图图层、组 |
| 透明度 | 支持 per-pixel alpha 与图层 opacity |
| 图层结构 | 任意深度嵌套组 |
| 混合模式 | `normal`、`multiply`、`add` |
| 压缩 | Raw、PackBits RLE |
| 图层名称 | Pascal name + Unicode `luni` |

## 唯一行为矩阵

中期实现必须按下表执行，不允许同一输入出现多种可选行为。

| 输入特性 | 输出行为 | Issue kind | Severity | 继续打开 |
|----------|----------|------------|----------|----------|
| PSD v2 / PSB | 拒绝打开，返回 `unsupportedVersion` 或等价错误 | 不生成报告 | error | 否 |
| 16/32 bit | 拒绝打开，返回 `unsupportedBitDepth` | 不生成报告 | error | 否 |
| CMYK / Lab / Indexed | 拒绝打开，返回 `unsupportedColorMode` | 不生成报告 | error | 否 |
| Zip / ZipPrediction 压缩 | 拒绝打开，返回 `unsupportedCompression` | 不生成报告 | error | 否 |
| 文字层 | 丢弃为可编辑图层，不进入图层树 | `unsupportedLayerKind` + `droppedLayer` | warning | 是 |
| 调整层 | 丢弃为可编辑图层，不进入图层树 | `unsupportedLayerKind` + `droppedLayer` | warning | 是 |
| 智能对象 | 丢弃为可编辑图层，不进入图层树 | `unsupportedLayerKind` + `droppedLayer` | warning | 是 |
| 图层样式 | 忽略样式，保留像素层本体 | `unsupportedLayerEffect` | warning | 是 |
| 图层蒙版 | 忽略蒙版，保留图层像素 | `unsupportedMask` | warning | 是 |
| 未支持混合模式 | 图层导入为 `normal` | `unsupportedBlendMode` | warning | 是 |

说明：

- “丢弃为可编辑图层”表示该 PSD layer 不进入 PSDKit 的 `GroupLayer` / `PixelLayer` 可编辑树；中期不承诺从 composite image 恢复该层。
- 拒绝打开的文件不会产生 `PSDDocument`，因此不要求生成 `PSDCompatibilityReport`。
- 如果后续要把 Zip 压缩从“拒绝”扩展为“跳过图层并继续打开”，必须通过新的 read option 和新测试显式引入。

## 设计任务

1. 定义 `Supported PSD Subset` 的正式文档。
2. 对照当前代码列出每个字段的读写位置。
3. 按唯一行为矩阵建立「支持 / 降级 / 拒绝」三类策略。
4. 为每个不支持特性定义用户可读提示文案。
5. 把支持子集同步到 README、测试说明和 API 文档。

## 实施任务

1. 新增或更新 `BlendMode`，只暴露中期支持的三种可创建模式。
2. 明确不支持 PSD 特性对应的 `PSDError` 或兼容性 warning。
3. 在读取路径中识别不支持特性，不允许静默转换。
4. 在写入路径中禁止写出支持子集外的公开模型。
5. 在测试 fixture 里加入每个不支持特性的最小样本。

## 验收步骤

1. 阅读 `README.md` 和 `docs/04-api-design.md`，确认支持范围描述一致。
2. 运行 `swift test`，确认既有 8-bit RGB fixture 全部通过。
3. 用 fixture 验证 16-bit、CMYK、PSB 等文件被拒绝，并返回明确错误。
4. 用 Zip / ZipPrediction fixture 验证文件被拒绝，返回 `unsupportedCompression` 或等价明确错误。
5. 用含未知混合模式的 PSD 验证打开成功、图层降级为 `normal`、兼容性报告包含该图层。
6. 用含文字层、调整层、智能对象的 PSD 验证对应层不进入可编辑图层树，并且报告包含 dropped issue。
7. 用含图层样式、蒙版的 PSD 验证像素层可保留，但样式和蒙版被报告为忽略。
8. 代码审查时确认没有新增私有 manifest、私有 image resource 或自定义 tagged block。

## 交付物

- 支持子集文档。
- 降级规则表。
- 对应 fixture 与测试。
- README 与 API 文档更新。

## 风险

| 风险 | 缓解 |
|------|------|
| 外部 PSD 结构复杂，识别不完整 | 先覆盖最常见的不支持类型，再用真实文件补充 |
| 降级规则和用户预期不一致 | 所有降级必须进入兼容性报告 |
| 未来画板特性超出 PSD 标准表达 | 先不加入该特性，或重新评估是否仍以 PSD 为唯一持久化格式 |

