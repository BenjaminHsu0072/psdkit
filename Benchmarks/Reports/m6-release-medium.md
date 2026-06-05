# PSDKit Benchmark

- Preset: `medium`
- Canvas: 2048×2048
- Pixel layers: 50
- Generated at: 2026-06-04T18:41:48Z

## Environment

| Field | Value |
|---|---|
| OS | Version 26.3.1 (a) (Build 25D771280a) |
| Hardware | Mac16,10, 10 logical CPUs, 16.0 GB RAM |
| Physical RAM | 16384.00 MB |
| Swift | swift-driver version: 1.127.15 Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2) Target: arm64-apple-macosx26.0 |
| Build | release |
| Warmup iterations | 1 |
| Measured iterations | 5 |
| Statistics | P50, P95, min, max over measured iterations (linear interpolation) |
| Peak memory | mach_task_basic_info.resident_size max sampled around each measured iteration |

## Metrics (seconds)

| Operation | Min | P50 | P95 | Max |
|---|---:|---:|---:|---:|
| Load | 0.0151 | 0.0175 | 0.0219 | 0.0227 |
| Semantic save | 0.2333 | 0.3079 | 0.3349 | 0.3355 |
| Composite | 0.0567 | 0.0733 | 0.1300 | 0.1425 |

## File size

- Semantic PSD size: **17072060** bytes (16.28 MB)

## Peak memory (resident)

- Sampled peak: **423.20 MB** (443760640 bytes)
- Note: mach_task_basic_info.resident_size max sampled around each measured iteration