#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
riff_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/riffnode-tests.XXXXXX")
trap 'rm -rf "$riff_test_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  RiffNode.swiftpm/Domain/Models/*.swift \
  RiffNode.swiftpm/Domain/Protocols/AudioProtocols.swift \
  RiffNode.swiftpm/Data/Analysis/FFTAnalyzer.swift \
  RiffNode.swiftpm/Data/Analysis/ChordDetector.swift \
  RiffNode.swiftpm/Data/AI/ToneRecipeBook.swift \
  RiffNode.swiftpm/Data/AI/SemanticCommandProcessor.swift \
  RiffNode.swiftpm/Presentation/ViewModels/SetupViewModel.swift \
  RiffNode.swiftpm/Presentation/ViewModels/AIChatbotController.swift \
  Tests/CoreRegressionTests.swift \
  -o "$riff_test_dir/core-tests"
"$riff_test_dir/core-tests"
