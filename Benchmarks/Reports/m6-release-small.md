# PSDKit Benchmark

- Preset: `small`
- Canvas: 1024×1024
- Pixel layers: 20
- Generated at: 2026-06-04T18:41:45Z

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
| Load | 0.0043 | 0.0044 | 0.0046 | 0.0046 |
| Semantic save | 0.0610 | 0.0620 | 0.0631 | 0.0633 |
| Composite | 0.0126 | 0.0127 | 0.0128 | 0.0128 |

## File size

- Semantic PSD size: **3818232** bytes (3.64 MB)

## Peak memory (resident)

- Sampled peak: **104.78 MB** (109871104 bytes)
- Note: mach_task_basic_info.resident_size max sampled around each measured iteration