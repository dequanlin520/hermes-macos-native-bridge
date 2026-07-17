#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$repo_root"

mkdir -p "$repo_root/artifacts/m2-008"

swift build --product HermesBridgeService
HERMES_RUN_MACH_SERVICE_INTEGRATION=1 \
  swift test --filter HermesBridgeServiceMachIntegrationTests/testTemporaryLaunchAgentMachServiceRoundTrip
