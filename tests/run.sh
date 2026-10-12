#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
bash -n linux-agent/install.sh
PULSE_TEST_FIXTURE="$TEST_DIR/linux-stats.json" python3 tests/test_linux_agent.py
swiftc -module-cache-path "$TEST_DIR/module-cache" Shared/PulseSettings.swift Shared/SharedStore.swift Shared/StatsModels.swift tests/TestStores.swift tests/main.swift -o "$TEST_DIR/store-tests"
"$TEST_DIR/store-tests" "$TEST_DIR/linux-stats.json"

bash -n linux-agent/pair.sh
python3 tests/test_pairing_agent.py
python3 tests/pairing_test_server.py "$TEST_DIR" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT
for attempt in {1..100}; do
    [[ -f "$TEST_DIR/pairing-server.json" ]] && break
    sleep 0.1
done
swiftc -parse-as-library -module-cache-path "$TEST_DIR/module-cache" Shared/PulseSettings.swift Shared/StatsModels.swift Shared/StatsClient.swift Shared/SecureHTTP.swift Shared/PairingProtocol.swift tests/TestStores.swift tests/PairingIntegration.swift -o "$TEST_DIR/pairing-tests"
"$TEST_DIR/pairing-tests" "$TEST_DIR/pairing-server.json"
