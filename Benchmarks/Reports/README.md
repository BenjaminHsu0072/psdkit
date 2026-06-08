# PSDKit benchmark reports

Release baseline artifacts for midterm M6 (`docs/midterm-plan/06-performance.md`).

## Reproduce

```bash
cd /path/to/psdkit
swift run -c release PSDKitBenchmark --preset small --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/m6-release-small.json
swift run -c release PSDKitBenchmark --preset medium --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/m6-release-medium.json
swift run -c release PSDKitBenchmark --preset stress --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/m6-release-stress.json
```

Generate PSD fixtures without measuring:

```bash
swift run -c release PSDKitBenchmark --generate-only /tmp/psdkit-fixtures
```

## Files

| File | Preset |
|------|--------|
| `m6-release-small.json` / `.md` | 1024×1024, 20 layers |
| `m6-release-medium.json` / `.md` | 2048×2048, 50 layers |
| `m6-release-stress.json` / `.md` | 4096×4096, 100 layers |

Summary and threshold comparison: [docs/m6-performance-baseline.md](../../docs/m6-performance-baseline.md).

## Editor E6 baseline

Record-only editor metrics (no pass/fail thresholds; not a CI hard gate). Thresholds in `docs/editor-plan/09-e6-validation-and-performance.md` are for manual comparison only.

```bash
./Scripts/run-editor-benchmark.sh
```

| File | Fixture |
|------|---------|
| `editor-e6-baseline-smoke.json` | Midterm standard document; snapshot build, CPU/Metal composite, brush rasterize, texture cache diagnostics |

**Measurement note:** `metalComposite` creates a new `EditorMetalRenderer` per measured iteration, so the sample includes renderer initialization cost—not steady-state composite frame time. A future release/perf pass may add a separate steady-state metric with a reused renderer.
