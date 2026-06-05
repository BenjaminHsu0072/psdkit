# M6 性能正式 Baseline（Release）

> 对应子计划：[midterm-plan/06-performance.md](./midterm-plan/06-performance.md)  
> 原始 JSON/Markdown 报告：[Benchmarks/Reports/](../Benchmarks/Reports/)  
> 生成时间（UTC）：2026-06-04（本机本地跑数，见各报告 `generatedAt`）

## 结论摘要

- **三档（Small / Medium / Stress）在 Release、warmup=1、iterations=5 下全部满足中期 P50 耗时与峰值内存阈值。**
- **P95 均未超过同档 P50 的 2 倍。**
- **Stress 档在本机（16 GB RAM）约 9s 完成，无 OOM。**
- **不建议进入第三轮（Accelerate / SIMD / Metal）**；前两轮结构优化后 CPU 路径已大幅优于目标。

## 运行环境

| 项 | 值 |
|----|-----|
| 硬件 | Mac16,10，10 逻辑 CPU，16 GB 物理内存 |
| 系统 | macOS Version 26.3.1 (a) (Build 25D771280a) |
| Swift | Apple Swift 6.2.4（`swift --version`，见 JSON `environment.swiftVersion`） |
| 构建 | `swift run -c release` → `buildConfiguration: release` |
| 轮次 | warmup=1，measured=5 |
| 统计 | P50、P95、min、max（线性插值百分位） |
| 峰值内存 | `mach_task_basic_info.resident_size`，每轮 load/save/composite 后采样取 max |

## 复现命令

```bash
swift test --filter PerformanceFixtureFactoryTests
swift test
swift run -c release PSDKitBenchmark --preset small --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/m6-release-small.json
swift run -c release PSDKitBenchmark --preset medium --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/m6-release-medium.json
swift run -c release PSDKitBenchmark --preset stress --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/m6-release-stress.json
cd Apps/PSDViewer && swift test && swift build
```

## Release 结果摘要

### Small（1024×1024，20 图层）

| 指标 | P50 | P95 | 阈值 (P50) | 通过 |
|------|-----|-----|------------|------|
| Load | 0.0040 s | 0.0041 s | ≤ 1.0 s | ✓ |
| Semantic save | 0.0573 s | 0.0577 s | ≤ 1.5 s | ✓ |
| Composite | 0.0123 s | 0.0124 s | ≤ 0.5 s | ✓ |
| 峰值内存 | 96 MB | — | ≤ 600 MB | ✓ |
| 文件大小 | 3.64 MB | — | — | — |

P95 / P50：load 1.02×，save 1.01×，composite 1.00×（均 ≤ 2×）。

### Medium（2048×2048，50 图层）

| 指标 | P50 | P95 | 阈值 (P50) | 通过 |
|------|-----|-----|------------|------|
| Load | 0.0157 s | 0.0190 s | ≤ 4.0 s | ✓ |
| Semantic save | 0.2322 s | 0.2436 s | ≤ 6.0 s | ✓ |
| Composite | 0.0579 s | 0.0670 s | ≤ 2.0 s | ✓ |
| 峰值内存 | 401 MB | — | ≤ 2.5 GB | ✓ |
| 文件大小 | 16.3 MB | — | — | — |

P95 / P50：load 1.21×，save 1.05×，composite 1.16×。

### Stress（4096×4096，100 图层）

| 指标 | P50 | P95 | 阈值 (P50) | 通过 |
|------|-----|-----|------------|------|
| Load | 0.0691 s | 0.0701 s | ≤ 20.0 s | ✓ |
| Semantic save | 0.9017 s | 0.9079 s | ≤ 35.0 s | ✓ |
| Composite | 0.2087 s | 0.2094 s | ≤ 8.0 s | ✓ |
| 峰值内存 | 1.37 GB | — | ≤ 8 GB | ✓ |
| 文件大小 | 65.7 MB | — | — | — |

P95 / P50：load 1.01×，save 1.01×，composite 1.00×。本机 16 GB 内存下顺利完成，无 OOM。

### 相对缩放（粗查线性）

以 Small 为参考，像素面积约 Medium 4×、Stress 16×；Load P50 约 3.9× / 17.1×，Save P50 约 4.1× / 15.7×，Composite P50 约 4.7× / 16.9×。未见明显指数级退化。

## 基础设施验收（对照 06-performance.md）

| 验收项 | 状态 |
|--------|------|
| 一键生成 Small / Medium / Stress（及 smoke） | ✓ `--generate-only` 输出四档 PSD |
| 输出 load / save / composite / file size | ✓ |
| 环境、Swift、构建配置、轮次、统计口径 | ✓ JSON + Markdown；含真实 `swift --version` 与硬件摘要 |
| 常规 `swift test` 不含重 benchmark | ✓ 仅 `PerformanceFixtureFactoryTests` 轻量用例 |
| Allocation count | 未采集（计划指标表中有，验收步骤未强制） |

## 第三轮平台优化建议

**不建议进入。** 当前 Release baseline 相对阈值有数量级余量；继续投入 Accelerate/vImage、SIMD 或 Metal 的性价比低，且会增加维护与 golden 对齐成本。若未来档位提高或合成算法扩展，再重新评估。

## 测试与构建（本包执行）

| 命令 | 结果 |
|------|------|
| `swift test --filter PerformanceFixtureFactoryTests` | 3 passed |
| `swift test` | 106 executed，1 skipped，0 failures |
| `swift run -c release PSDKitBenchmark`（三档） | 均成功，报告已写入 `Benchmarks/Reports/` |
| `cd Apps/PSDViewer && swift test && swift build` | 11 passed，build OK |

## Fixture / manifest

- `Tests/PSDKitTests/Fixtures`：**无 git diff**（本任务未生成或修改测试 PSD fixture）。
- `Tests/PSDKitTests/Golden/manifest.json`：**无 diff**。

## 未解决问题与风险

1. **峰值内存为进程 resident 采样**，非 Instruments 级精确峰值；低内存机器上 Stress 仍可能接近系统限制，需在 16 GB 以下环境复测。
2. **未实现 Allocation count** 与 Raw vs RLE 分档文件大小对比。
3. **基准仅在单台 Mac16,10 上采集**；CI smoke 与正式验收分离的策略仍适用。
4. **P50 阈值偏保守**：首次 baseline 远优于表内目标，后续可在文档中收紧阈值而不改代码。

## M6 收尾代码改动（本包）

- `Benchmarks/PSDKitPerformanceFixtures/PerformanceBenchmarkMetadata.swift`：真实 `swift --version`、硬件与物理内存。
- `Benchmarks/PSDKitBenchmark/`：`EnvironmentInfo`、`BenchmarkRunner`、`BenchmarkOutput`、`TaskMemorySampler`：报告字段与峰值内存采样。
- `Tests/PSDKitTests/PerformanceFixtureFactoryTests.swift`：元数据轻量测试。
- `Benchmarks/Reports/*`：Release JSON/Markdown 报告与 README。
- 本文档：`docs/m6-performance-baseline.md`。
