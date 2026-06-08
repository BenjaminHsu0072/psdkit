#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/Benchmarks/Reports/editor-e6-baseline-smoke.json}"
mkdir -p "$(dirname "$OUTPUT")"

cd "$ROOT/Apps/PSDViewer"
EDITOR_BENCHMARK_OUTPUT="$OUTPUT" swift test --filter EditorBenchmarkSmokeTests

echo "Editor benchmark report: $OUTPUT"
