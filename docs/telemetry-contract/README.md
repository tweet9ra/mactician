# Telemetry schema v2 contract

These JSON files are the canonical public wire examples for Mactician telemetry,
including the legacy first-session event, the fresh activation snapshot, the
anonymous daily-active heartbeat and per-session summary, and consented extended
diagnostics, plus cumulative `game_session_performance` checkpoints for all users.
Performance events omit `consent_version` and do not depend on the optional choice.
Performance uses 85 noncumulative SurfaceFlinger bucket counts per segment;
the bucket order and semantics are documented in `../performance-telemetry.md`.
The Swift tests verify the encoded key sets and the private API repository keeps
byte-identical copies for its HTTP contract tests. Run
`scripts/verify-telemetry-contract.command` before a server or launcher release.

Schema v2 intentionally contains no installation identifier, account identity,
network address, host name, serial number, MAC address, or game logs. Unknown
fields are rejected by the server.

`game-session-performance-v2.json` retains the legacy shape.
`game-session-performance-diagnostics-v2.json` adds optional loss diagnostics v1;
its counters describe one unknown non-gameplay window as well as successful
combat and a missing frame window. See [field semantics](performance-diagnostics.md).
Old attempts must not acquire this block during checkpoint recovery.

`game-session-performance-log-context-v2.json` covers schema-v2 events with diagnostics v3 and bounded log-based lifecycle/activity contexts. Older fixtures remain unchanged.
