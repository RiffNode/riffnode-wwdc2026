#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
riff_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/riffnode-audio-tests.XXXXXX")
trap 'rm -rf "$riff_test_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  RiffNode.swiftpm/Domain/Models/*.swift \
  RiffNode.swiftpm/Domain/Protocols/*.swift \
  RiffNode.swiftpm/Data/Audio/DSP/*.swift \
  RiffNode.swiftpm/Data/Audio/DemoRiffSynthesizer.swift \
  RiffNode.swiftpm/Data/Audio/DemoRiffPlayer.swift \
  Tests/AudioGraphRegressionTests.swift \
  -o "$riff_test_dir/audio-tests"
"$riff_test_dir/audio-tests"
