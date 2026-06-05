# PSDKit Benchmark

- Preset: `stress`
- Canvas: 4096×4096
- Pixel layers: 100
- Generated at: 2026-06-04T18:41:57Z

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
| Load | 0.0671 | 0.0683 | 0.0702 | 0.0704 |
| Semantic save | 0.9068 | 0.9099 | 0.9173 | 0.9176 |
| Composite | 0.2084 | 0.2084 | 0.2109 | 0.2113 |

## File size

- Semantic PSD size: **68856408** bytes (65.67 MB)

## Peak memory (resident)

- Sampled peak: **1398.34 MB** (1466269696 bytes)
- Note: mach_task_basic_info.resident_size max sampled around each measured iteration