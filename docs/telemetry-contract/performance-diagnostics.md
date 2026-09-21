# Performance loss diagnostics v1

Optional `performance.diagnostics` is present on newly instrumented attempts and
absent on legacy attempts. It is standard performance collection, independent of
the optional Extended Diagnostics choice. No new event type or histogram segment
dimension is introduced. The canonical example is
`game-session-performance-diagnostics-v2.json`.

`version` is `1`; `implementation` is `screen-bracket-diagnostics-v1`; `language`
is a supported requested game-language code or `unknown`. These fields are fixed
for the attempt. The algorithm identifier remains `screen-bracket-v1`: diagnostic
metadata does not change scene classification. Different implementations remain
separate in performance comparisons.

All maps contain only allowlisted keys. Missing keys mean zero within a present
diagnostics object. An absent object means **not collected**. Counts are cumulative,
nonnegative and cannot decrease or be relabelled in subsequent revisions.

| Map | Denominator / invariant |
| --- | --- |
| `measurements` | Exactly one outcome per foreground measurement attempt; sum equals `windows_attempted`; `sampled` equals attempted minus missing |
| `contexts` | Exactly one outcome per accepted histogram window; sum equals `measurements.sampled`; gameplay/lobby match segment windows |
| `endpoints` | One outcome per attempted boundary classification, up to two per foreground measurement attempt |
| `states` | One coarse screen state per successfully decoded classifier response; sum equals non-error endpoint outcomes |
| `signals` | Overlapping `stage_read`, `phase_read`, `dimensions_match`, `dimensions_mismatch` counts; stage/phase bounded by decoded endpoints; matching and mismatching dimensions sum to dimension observations |
| `dimensions` | Supported size labels (`1920x1080`, `2560x1440`, `2880x1620`, `3200x1800`, `3840x2160`) or `other`, never arbitrary strings |

Measurement reasons: `sampled`, `lost_focus`, `timestats_failed`, `layer_not_found`,
`layer_changed`, `counter_reset`, `no_frames`, `invalid_duration`,
`invalid_histogram`, `segment_limit`, `measurement_failed`.

Endpoint reasons: `gameplay`, `lobby`, `non_gameplay`, `stage_unreadable`,
`phase_unrecognized`, `insufficient_evidence`, `helper_missing`, `capture_failed`,
`helper_timeout`, `helper_failed`, `unsupported_dimensions`, `invalid_image`,
`ocr_failed`, `invalid_response`. A known screen can still be rejected by the
unchanged gameplay classifier: for example patching or a reward-choice overlay.

Context reason precedence: stable gameplay/lobby; endpoint failure; state change;
round change; phase change; stable recognized non-gameplay; one unknown endpoint;
both unknown endpoints. A round change stays unknown even within the same coarse
stage band. Raw stage/phase values only pass between local processes; the uploaded
block contains counts and coarse states, not stage strings or OCR evidence.

`timings` holds noncumulative histograms for `screencap`, `classifier`, `timestats`,
`before_gap`, `after_gap`, `cycle`, `interval`. Upper bounds in milliseconds are
`[100, 500, 1000, 2500, 5000, 10000, 30000, 60000, 180000, 600000, overflow]`.
The API limits observations by the maximum calls per check: two captures and
classifications, four TimeStats calls, one of each gap, one foreground interval,
one cycle (including background checks). These are wall times, not CPU load.

Before gap starts at screenshot acquisition invocation and ends after the frame
baseline. After gap runs from the final frame snapshot to screenshot invocation.
Neither is an exact guest capture timestamp. Interval is between foreground
measurement starts and may span a period in background. `backoff_windows` counts
foreground checks whose overhead extends the existing randomized sampling delay.

Deploy the compatible API before the client. Request size remains 32 KiB; the
latest-checkpoint queue remains at most 16 attempts / 256 KiB. Diagnostic counters
do not participate in frame percentile calculations. Suppression of small report
groups and the distinction between display floors and useful sample sizes remain.

## Passive game-log experiment (diagnostics v2)

New attempts use `version=2`, `implementation=screen-bracket-game-log-v2`.
The frame classifier remains `screen-bracket-v1`. Recovered v1 checkpoints keep
v1 and omit `game_log`; the API accepts both. Deploy API and privacy compatibility
before distributing the new launcher.

One read after each foreground collection cycle takes at most 64 KiB from the
current TFT log, with a two-second ADB deadline. It runs after TimeStats is
disabled and after both screenshot endpoints. Its cost is included in collector
wall time/backoff and a separate `timings.game_log` histogram (at most one per
foreground attempt). It never requests root, changes verbosity, writes guest
files or attaches to the game. Raw log bytes are processed only in memory and
are neither saved nor uploaded. PID/start ticks, file identity, timestamps,
account/player IDs, tokens and arbitrary log text never enter a checkpoint.

The reader checks process PID/start ticks and file inode/size before and after
the read, rejects replacement/truncation, ignores events predating this process
or in the future, and discards partial boundary lines. Guest wall clock and
uptime establish process age. No event is cached across reads, process restarts,
log rotation or reconnection. A successful read can contain no known events.

`game_log` has six cumulative allowlisted maps:

| Map | Meaning / denominator |
| --- | --- |
| `reads` | Exactly one per foreground attempt: observed, read_failed, game_not_running, log_unavailable, invalid_snapshot, log_changed |
| `lifecycle` | Latest recognized field in the bounded tail: none, gameflow_lobby, phase_matchmaking, phase_afk_check, phase_champion_select, state_in_progress; one per observed read |
| `lifecycle_age` | none, within_10s, within_60s, within_5m, older; one per observed read |
| `phase_events` | Latest GC departure: none, planning_departure, combat_departure, draft_departure; one per observed read, not unique events |
| `phase_age` | Same age buckets; one per observed read |
| `contexts_near_event` | Existing context outcome for an accepted frame window when the latest departure is at most ten seconds old at log read; bounded by recent reads and corresponding context counts |

Ages use the integer guest clock at read start; bucket boundaries have roughly
one second of clock rounding plus read latency, not screenshot-time precision.
Age buckets do not overlap. `none` totals must match the corresponding value
map. Every map is bounded, cannot decrease and rejects unknown keys. Background
checks have no log observation. Probe-enabled attempts have a separate report
stratum; old clients do not dilute the log-read denominator. Overall diagnostic
summaries may combine implementations, with each map retaining its denominator.
The canonical additive fixture is `game-session-performance-game-log-v2.json`.

A lifecycle field is not a current screen label. GC departure records are
conditional/incomplete and do not state the current phase. Nearby screen/log
observations are not evidence of agreement; their exact instants differ. No
round is inferred from event counts, no log observation changes a frame label,
and none makes an unknown window eligible as gameplay. This release experiment
measures source availability, freshness and cost before choosing a hybrid reader.

## Log-based context (diagnostics v3)

New attempts use `classifier=game-log-bracket-v1`, `version=3`,
`implementation=game-log-context-v1`. Old v1/v2 checkpoints keep their original
classifier and diagnostic identities on recovery. The API must support v3 before
these clients send data. The outer event remains schema version 2.

The performance collector no longer invokes screenshots or OCR. Two bounded,
passive reads surround the frame window: before TimeStats setup and after its
final snapshot/disable. Both reads must succeed, have the same process PID/start
identity and file inode, nondecreasing file size, and an increasing guest clock
no more than 15 seconds apart. A change or unavailable boundary yields unknown;
foreground and frame-histogram checks remain in force. The randomized 45–75 s
schedule and 1% wall-time duty backoff remain unchanged.

Each read independently considers only complete records from this process,
not future records. Recognized evidence expires after 60 seconds; nothing is
carried into the next read. Within one second, a more specific phase/game-state
message wins over its general gameflow LOBBY envelope. A newer unrecognized
lifecycle field invalidates older evidence. Later known lifecycle messages also
replace older match activity. This is recent log context, not proof of the
currently rendered screen, completed loading or a continuously observed match.

| `segments.scene` | Evidence |
| --- | --- |
| `lobby` | Recent `gameflowPhase=LOBBY` |
| `matchmaking` | Recent `phaseName=MATCHMAKING` |
| `match_starting` | Recent `AFK_CHECK`, `CHAMPION_SELECT`, or `gameState=IN_PROGRESS`; loading may still be in progress |
| `match_activity` | Recent allowlisted Planning/Combat/Draft departure from the runtime-performance subsystem; both scheduled and recently-skipped GC records count |
| `unknown` | No fresh evidence, failed/discontinuous read or different boundary contexts |

A GC departure is not the current phase. No departure count yields a round.
All v3 `stage_band` values must be `unknown`; combat/planning are rejected for
this classifier. Recent match activity has separately labelled descriptive frame
statistics. It does not contribute to matched gameplay comparisons, slow-session
eligibility or recognized planning/combat totals. Transitions and overlays may be
present. Keeping this distinction is essential when evaluating apparent unknown
reduction against legacy screenshot clients.

There are exactly two `game_log.reads` outcomes per foreground attempt, including
missing-frame attempts. Other read maps retain one observation per successful
read. `contexts_near_event` records at most one accepted window, based only on the
final read. Its recent-read denominator includes both boundaries and is not an
agreement or accuracy estimate. `timings.game_log` has at most two observations
per attempt. V3 has no endpoint/state/dimension/signal observations or screenshot,
classifier and capture-gap timing keys. Measurement reasons remain unchanged.
Context reasons are the four known scene labels, `both_unknown`, `state_changed`,
`endpoint_failed`, and `log_discontinuity`; scene counters equal segment windows.

Canonical fixture: `game-session-performance-log-context-v2.json`. The v2 suffix
names the outer event schema, not diagnostic version. Raw lines, event timestamps,
process/file identity, player/account information and arbitrary enums remain
local in memory and never enter telemetry.
