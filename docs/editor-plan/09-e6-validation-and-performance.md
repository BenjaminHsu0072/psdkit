# E6 验收与性能

## 阶段目标

建立 Editor 的交付质量闭环：自动化测试、手工验收、Photoshop roundtrip、性能基线和调试诊断。E6 不再补核心架构能力，而是确认 E0-E5 的结果可以稳定交付和持续演进。

## 验收层级

```text
Unit tests
    │
    ▼
Integration tests
    │
    ▼
Viewer / Editor manual validation
    │
    ▼
Photoshop roundtrip
    │
    ▼
Performance baseline
```

## 自动化测试范围

### EditorCore

覆盖：

- snapshot 构建。
- selection。
- tool state。
- command dispatch。
- undo/redo。
- dirty 语义。

### RenderCore

覆盖：

- layer order。
- blend / opacity 关键像素。
- texture cache invalidation。
- dirty region。
- viewport 映射。

### InputCore

覆盖：

- pointer sample。
- stroke session。
- view/canvas/layer 坐标映射。
- pressure clamp。
- stroke bounds。

### Writeback

覆盖：

- patch apply。
- patch inverse。
- readback metadata。
- save flush。
- reopen roundtrip。

## 手工验收清单

建议新增 `docs/editor-plan/10-editor-acceptance-checklist.md` 或纳入现有 manual validation plan。

### 基础打开与预览

- 打开标准 PSD。
- Metal preview 正确显示。
- `normal` / `multiply` / `add` 预览与 CPU reference 关键像素一致。
- 缩放、平移、适应窗口正常。
- 图层 frame overlay 对齐。
- Compatibility Report 入口可达，内容不因 Editor shell 重组丢失。

### 图层属性

- visibility 切换。
- opacity 修改。
- frame 移动。
- blend mode 修改。
- 保存后重新打开保持一致。

### 绘制

- 选中 pixel layer 后绘制。
- 未选中 pixel layer 时不能绘制。
- offset layer 绘制落点正确。
- 缩放和平移后绘制落点正确。
- 修改 brush size / color / opacity / flow。
- cancel stroke 不产生提交。

### undo/redo

- 单笔 undo。
- 多笔连续 undo。
- redo。
- undo 后保存。
- redo 后保存。

### 保存与关闭

- 绘制后 dirty 状态出现。
- 关闭时弹出 unsaved confirmation。
- Save 后 dirty 清除。
- Save As 后新文件可打开。
- 快速绘制后立即保存不丢 stroke。
- lossy save confirmation 三分支可达：View Details、Cancel Save、Continue Save。
- `pendingFlush` / `flushing` / `flushFailed` 下 save、close、undo、redo 行为符合 E5 状态机。

### Photoshop roundtrip

- Editor 保存 PSD。
- Photoshop 打开 PSD。
- 检查图层位置和绘制结果。
- Photoshop 另存后 PSDKit/Editor 重新打开。
- 对比关键视觉结果。

## 性能指标

### Preview

- 打开标准文档首帧时间。
- 图层属性变更后的 redraw 时间。
- 缩放/平移帧率。
- texture upload count。

### Brush

- stroke input latency。
- point consume delay。
- dab expansion time。
- active stroke stamp time。
- commit time。
- readback time。

### Memory

- layer texture count。
- active stroke texture memory。
- total estimated GPU memory。
- document close 后 texture 是否释放。

## 性能基线策略（当前实现）

E6 smoke benchmark（`EditorBenchmarkSmokeTests` / `./Scripts/run-editor-benchmark.sh`）当前为 **record-only baseline / diagnostics archive**：

- 输出 JSON 归档 P50/P95/min/max 与 texture/brush diagnostics，**不做 pass/fail 判定**。
- CI 不将性能指标作为 hard gate；`swift test` 仅验证报告结构可生成。
- 下文「建议目标」中的数值仅供**人工对比与同机回归参考**，不作为自动化阻塞条件。
- 相对 baseline 退化 `>15%` / `>30%` 的分级用于验收讨论与 Major 判定参考，需结合环境与测量口径解读。

### Smoke 测量口径说明

`metalComposite` 在每次测量迭代内调用 `EditorMetalRenderer.makeDefault()` 后执行合成，**包含 renderer 初始化成本**，不等同于 steady-state 复用 renderer 的帧时。后续 release/perf 专项可拆出「复用 renderer 的 steady-state composite」作为独立指标。

## 建议目标（人工对比参考）

初始目标不宜过度承诺，但必须可测。除非阶段文档另行冻结更严格标准，E6 使用以下参考阈值（**非 CI hard gate**）：

| 指标 | 参考阈值 | 统计口径 |
|------|----------|----------|
| Preview 关键像素误差 | 每通道 `0`；如浮点舍入已冻结，最多 `1` | 小尺寸 reference fixture，逐像素或关键点对比 |
| 打开标准文档首帧 | P95 `< 500 ms` | 连续 10 次本机测量，丢弃首次冷启动可另记 |
| 图层属性 redraw | P95 `< 100 ms` | visibility / opacity / frame / blend 各 10 次 |
| 缩放/平移 frame time | P95 `< 16.7 ms`，P99 `< 33.4 ms` | 60Hz 目标；记录连续交互 5 秒 |
| stroke sample 消费延迟 | P95 `< 16.7 ms`，P99 `< 33.4 ms` | active stroke 期间 point write 到 stamp consumed |
| stroke commit | P95 `< 100 ms` | 常规 brush、标准文档 layer |
| dirty region readback | P95 `< 150 ms` | 标准 dirty rect；full layer fallback 单独记录 |
| 性能回归红线 | 相对最近归档 baseline 退化 `> 15%` 建议标记 Major；`> 30%` 建议标记 Blocker | 同机器、同 fixture、同配置；**人工审阅参考**，非自动化判定 |

如果机器或 fixture 变化导致阈值不可比，必须在性能报告中记录环境，并建立新的 baseline，不能用主观“无明显卡顿”替代。

## 调试诊断

建议加入 Editor debug panel：

- current tool
- selected layer id
- viewport scale / offset
- texture count
- upload count
- dirty region
- active stroke point count
- consumed point count
- GPU frame time
- readback time
- last command
- undo stack count

调试信息应来自各模块公开 diagnostics，不应让 UI 直接读取内部 mutable state。

## 回归策略

- 每阶段保留 `swift test`。
- E6 前复跑 PSDKit 既有测试。
- 保留 M6 benchmark 作为库层回归锚点。
- 新增 Editor benchmark 时要区分 CPU 读写、Metal preview、brush 三类指标。
- 兼容报告、lossy save confirmation、unsaved close guard 属于流程回归固定项，每轮 Editor 手工验收都必须覆盖。

## 缺陷分级

### Blocker

- 保存后绘制结果丢失。
- Photoshop 无法打开保存文件。
- dirty 状态错误导致用户编辑丢失。
- 绘制写入错误图层。
- `flushFailed` 状态下允许保存并清 dirty。
- 默认预览路径对 `normal` / `multiply` / `add` 产生不可解释的关键像素差异。

### Major

- preview 与保存结果明显不一致。
- undo/redo 导致 texture 和文档不同步。
- 性能相对 baseline 退化超过 `15%`（人工审阅参考，非 CI 自动阻塞）。
- 坐标在缩放/平移后明显偏移。
- Compatibility Report 或 lossy save confirmation 分支不可达。

### Minor

- diagnostics 不完整。
- 状态文案不准确。
- 非核心 brush 参数体验不佳。

## 验收 gate

- `swift test` 通过。
- Editor 手工验收 checklist 通过。
- Photoshop roundtrip 通过。
- 性能 smoke 基线已记录归档（record-only；不做自动化阈值判定）。
- 关键像素误差、frame time、stroke commit、readback 等指标已对照「建议目标」参考阈值做人工审阅，或有明确 baseline 更新记录与说明。
- 兼容报告、lossy save confirmation、unsaved close guard 回归通过。
- Blocker/Major 缺陷清零或有明确延期决策。

## 交付物

- Editor acceptance checklist → [10-editor-acceptance-checklist.md](./10-editor-acceptance-checklist.md)。
- 性能报告 → `Benchmarks/Reports/editor-e6-baseline-smoke.json`（由 `EditorBenchmarkSmokeTests` / `EditorBenchmarkRunner` 生成；record-only）。
- Photoshop roundtrip 证据。
- 已知问题列表。
- 下一阶段优化建议。

## 一键自动化命令

```bash
# E6 umbrella + E1–E5 关键 editor 测试
cd Apps/PSDViewer && swift test --filter 'EditorE6|Editor|Brush|Stroke|Writeback|Undo|LayerTextureCache|DocumentModelCompatibilityTests'

# PSDViewer 全量 + 库层回归
cd Apps/PSDViewer && swift test
swift test

# E6 性能/diagnostics 基线（record-only，无 CI 硬阈值）
./Scripts/run-editor-benchmark.sh
# 或：
cd Apps/PSDViewer && EDITOR_BENCHMARK_OUTPUT=../../Benchmarks/Reports/editor-e6-baseline-smoke.json \
  swift test --filter EditorBenchmarkSmokeTests
```

### 自动化 gate 与测试文件映射

| Gate | 主要测试 |
|------|----------|
| E0 模块边界 | `EditorDependencyBoundaryTests` |
| E1 Metal preview / CPU fallback | `EditorPreviewRoutingTests`, `EditorSnapshotCompositorTests`, `EditorE6SmokeTests` |
| E2 LayerTextureCache | `LayerTextureCacheTests`, `TextureInvalidationTests` |
| E3 输入与坐标 | `EditorInputTests`, `InputCoordinateMapperTests`, `StrokeSessionTests` |
| E4 brush determinism | `EditorMetalBrushPipelineTests`, `BrushDabPlannerTests`, `StrokePreviewLifecycleTests` |
| E5 writeback/undo/save/close | `EditorWritebackTests`, `EditorCommandDispatcherTests`, `EditorStateTests` |
| E6 reference | `EditorE6SmokeTests`（Metal vs CPU composite、writeback composite 可见） |

GPU/Metal 测试在设备不可用时 `XCTSkip`，不应导致 CI 偶发失败。
