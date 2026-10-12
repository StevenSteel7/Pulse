#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
bash -n linux-agent/install.sh
PULSE_TEST_FIXTURE="$TEST_DIR/linux-stats.json" python3 tests/test_linux_agent.py
swiftc -module-cache-path "$TEST_DIR/module-cache" Shared/PulseSettings.swift Shared/SharedStore.swift Shared/StatsModels.swift tests/main.swift -o "$TEST_DIR/store-tests"
"$TEST_DIR/store-tests" "$TEST_DIR/linux-stats.json"
