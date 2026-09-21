#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly CONTRACT_DIR="$PROJECT_DIR/docs/telemetry-contract"
readonly API_CONTRACT_DIR="${MACTICIAN_API_CONTRACT_DIR:-$PROJECT_DIR/../sergeinaumov.dev/server/mactician-api/testdata/contract}"

(
    cd "$CONTRACT_DIR"
    shasum -a 256 -c SHA256SUMS
)

if [[ -d "$API_CONTRACT_DIR" ]]; then
    for fixture in activation-snapshot-v2.json daily-active-v2.json first-game-session-v2.json game-session-diagnostics-v2.json game-session-summary-v2.json game-session-performance-v2.json game-session-performance-diagnostics-v2.json game-session-performance-game-log-v2.json game-session-performance-log-context-v2.json SHA256SUMS; do
        cmp -s "$CONTRACT_DIR/$fixture" "$API_CONTRACT_DIR/$fixture" || {
            print -u2 "Telemetry contract drift: $fixture differs from $API_CONTRACT_DIR/$fixture"
            exit 1
        }
    done
    print "Launcher and API telemetry contracts match."
else
    print "API contract directory not present; canonical launcher fixture hashes are valid."
fi
