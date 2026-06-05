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
