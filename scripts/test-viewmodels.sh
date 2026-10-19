#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
riff_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/riffnode-vm-tests.XXXXXX")
trap 'rm -rf "$riff_test_dir"' EXIT
# MainViewModel against fakes: only the Domain, the dependency container and the view models.
xcrun swiftc -swift-version 6 -parse-as-library \
  RiffNode.swiftpm/Domain/Models/*.swift \
  RiffNode.swiftpm/Domain/Protocols/*.swift \
  RiffNode.swiftpm/App/AppDependencies.swift \
  RiffNode.swiftpm/Presentation/ViewModels/MainViewModel.swift \
  RiffNode.swiftpm/Presentation/ViewModels/BoardHistory.swift \
  RiffNode.swiftpm/Presentation/ViewModels/AIChatbotController.swift \
  RiffNode.swiftpm/Presentation/ViewModels/PerformanceModeController.swift \
  RiffNode.swiftpm/Presentation/ViewModels/RiffNotchController.swift \
  RiffNode.swiftpm/Presentation/DesignSystem/DomainColors.swift \
  RiffNode.swiftpm/Presentation/DesignSystem/DesignSystem.swift \
  Tests/ViewModelTests.swift \
  -o "$riff_test_dir/vm-tests"
"$riff_test_dir/vm-tests"
