# 子计划 6：性能基准与优化

## 目标

让 PSDKit 在中等规模画板文档上达到可用性能，并用 benchmark 数据说明性能边界。

性能目标不追求 Photoshop 级别，但必须满足：

- 小文档操作流畅。
- 中文档打开、保存、预览在可接受时间内完成。
- 压力文档不应轻易 OOM。
- 优化有数据支撑，而不是凭感觉改代码。

## 基准档位

| 档位 | 画布 | 图层 | Load P50 | Save P50 | Composite P50 | 峰值内存 |
|------|------|------|----------|----------|---------------|----------|
| Small | 1024x1024 | 20 | <= 1.0s | <= 1.5s | <= 0.5s | <= 600 MB |
| Medium | 2048x2048 | 50 | <= 4.0s | <= 6.0s | <= 2.0s | <= 2.5 GB |
| Stress | 4096x4096 | 100 | <= 20.0s | <= 35.0s | <= 8.0s | <= 8 GB |

阈值是中期第一版目标，允许在首次 baseline 后通过文档修订调整，但调整必须附 benchmark 结果。

图层内容应包含：

- 全画布图层。
- 小尺寸 offset 图层。
- alpha 渐变图层。
- 三种 blend mode。
- 两层以上嵌套组。

## 指标

| 指标 | 说明 |
|------|------|
| Load time | `PSDDocument.load` 总耗时 |
| Save time | semantic save 总耗时 |
| Composite time | `compositePreviewRGBA` 总耗时 |
| Peak memory | 打开和保存时峰值内存 |
| File size | RLE 与 Raw 写出大小 |
| Allocation count | 热路径临时分配数量 |

## 基线环境与统计口径

性能数据必须记录运行环境，避免不可比较的结果进入验收。

默认基线环境：

| 项 | 要求 |
|----|------|
| 硬件 | Apple Silicon Mac，至少 16 GB 内存 |
| 系统 | macOS，记录具体版本 |
| Swift | 记录 `swift --version` |
| 构建配置 | Release，启用优化 |
| 运行轮次 | 每个 benchmark 预热 1 次，正式运行 5 次 |
| 统计口径 | 记录 P50、P95、最小值、最大值 |
| 波动容忍 | 同一机器 P50 回归超过 15% 需要解释 |
| 后台负载 | 运行前关闭明显 CPU / IO 重负载任务 |

如果在 CI 上运行轻量性能 smoke，CI 结果只用于发现明显退化，不作为正式性能验收。

## 热路径

| 优先级 | 模块 | 关注点 |
|--------|------|--------|
| P0 | `CompositeBuilder` | 避免整层拷贝，减少 `Double` 运算，支持局部 bounds |
| P0 | `PlanarRGBA` | interleave/deinterleave 减少中间 buffer |
| P1 | `PackBitsCodec` | 编码/解码减少重复分配 |
| P1 | `ChannelDecompressor` | 通道解压可并行化 |
| P1 | `PSDWriter` | 保存时避免不必要的 composite 重算 |
| P2 | `PSDDocument` 内存模型 | 大文件避免长期保留重复 `Data` |

## 设计任务

1. 建立 benchmark target 或独立脚本。
2. 定义可重复生成的性能 fixture。
3. 确定每个指标的采集方式。
4. 按基线环境记录首次 baseline，并确认或修订上方阈值。
5. 决定哪些优化可进入中期，哪些留到后续。

## 实施任务

1. 新增 `Benchmarks/` 或 Swift executable target。
2. 生成 Small / Medium / Stress 三档 PSD。
3. 输出 JSON 或 Markdown 结果，便于记录历史。
4. 对 `CompositeBuilder` 做第一轮优化。
5. 对 `PlanarRGBA` 做第一轮优化。
6. 对 RLE 编解码做分配和循环优化。
7. 用 benchmark 比较优化前后结果。

## 优化建议顺序

### 第一轮：低风险优化

1. 移除 `CompositeBuilder` 中不必要的整层 `Data` 拷贝。
2. 将合成循环从 `Double` 改为整数或 `Float`，并用 golden 测试确认结果。
3. 只遍历图层与画布相交区域。
4. 避免在每个像素循环中重复计算常量。
5. 复用临时 buffer。

### 第二轮：结构优化

1. `PlanarRGBA` 支持直接写入预分配 buffer。
2. RLE 编码按行处理，减少大块中间数组。
3. 通道解压和编码使用 task group 并行。
4. 保存时仅在内容变化时重算 composite。

### 第三轮：平台优化

1. 评估 Accelerate / vImage。
2. 评估 SIMD。
3. 如画板本身使用 GPU，再评估 Metal 合成。

第三轮不作为中期必须项，除非前两轮不能达到性能目标。

## 验收步骤

1. benchmark 能一键生成三档测试文档。
2. benchmark 能输出 load/save/composite/file size 指标。
3. benchmark 输出必须包含硬件、系统、Swift 版本、构建配置、运行轮次和统计口径。
4. Small / Medium / Stress 三档 P50 与峰值内存满足基准档位表。
5. P95 不超过同档 P50 的 2 倍；超过时必须记录原因。
6. Stress 档不 OOM；耗时增长应与像素数和图层数近似线性相关，不能出现明显指数级退化。
7. 每个性能优化 PR 都附带优化前后 benchmark 对比；同机 P50 回归超过 15% 需要解释。
8. 优化后 golden 像素测试仍通过，特别是三种 blend mode 的合成结果。

## 测试建议

- `PerformanceFixtureFactory`：生成三档文档。
- `PSDKitBenchmark`：命令行 benchmark。
- `CompositeBuilderPerformanceTests`：只保留轻量级 smoke，不把重 benchmark 放进常规 `swift test`。
- `PlanarRGBAPerformanceTests`：小样本分配与耗时回归。

## 风险

| 风险 | 缓解 |
|------|------|
| 性能测试不稳定 | 每个 benchmark 重复多轮，记录中位数 |
| 优化改变像素结果 | 所有优化必须跑 golden 像素测试 |
| 并行引入数据竞争 | 文档模型保持主线程/单 owner，热路径只并行纯函数 |
| 过早引入 Metal 增加复杂度 | 先完成 CPU baseline 和低风险优化 |

