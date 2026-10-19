#!/bin/bash
# Times RiffNode's DSP against the real-time budget. Optional: a .nam capture to time too.
#   scripts/bench-audio.sh [capture.nam]
set -euo pipefail
cd "$(dirname "$0")/.."
riff_bench_dir=$(mktemp -d "${TMPDIR:-/tmp}/riffnode-bench.XXXXXX")
trap 'rm -rf "$riff_bench_dir"' EXIT
xcrun swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos26.0" -parse-as-library \
  RiffNode.swiftpm/Domain/Models/*.swift \
  RiffNode.swiftpm/Domain/Protocols/*.swift \
  RiffNode.swiftpm/Data/Audio/DSP/*.swift \
  RiffNode.swiftpm/Data/Audio/DemoRiffSynthesizer.swift \
  RiffNode.swiftpm/Data/Audio/DemoRiffPlayer.swift \
  Tests/AudioBenchmark.swift \
  -o "$riff_bench_dir/bench"
"$riff_bench_dir/bench" "$@"
