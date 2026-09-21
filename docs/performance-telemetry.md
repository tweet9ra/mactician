# Performance telemetry and update evaluation

Implemented locally on 2026-09-08. Player collection starts only after deployment,
a launcher release. Performance collection covers every Android launch regardless
of the optional Extended Diagnostics choice. No production baseline
or improvement claim is available yet.

## Industry evidence and decisions

| Primary source | Practice used here |
| --- | --- |
| [Riot: VALORANT Global Invalidation](https://playvalorant.com/en-us/news/dev/performance-boost-valorant-s-global-invalidation/) | Compare hardware and game context, inspect regressions across configurations; keep an optimization reversible. |
| [Epic: reducing Fortnite power consumption](https://cdn2.unrealengine.com/reducing-fortnites-power-consumption-layout-v03-ffedbeb1adeb.pdf) | Measure actual activation and quality/power tradeoffs, with staged rollout. Mactician records detected cache activation; power itself is not measured in this first implementation. |
| [Android slow sessions](https://developer.android.com/topic/performance/vitals/slow-session) | Inspect slow-frame tails and a per-session slow fraction; separate startup. Mactician uses an explicitly labelled estimate from samples, not the Android vitals metric. |
| [Android frame statistics](https://developer.android.com/games/optimize/framerate?hl=en) | Use presentation timing from SurfaceFlinger. Guest presentation is a proxy for player experience, not host display or input latency. |
| [AOSP histogram implementation](https://android.googlesource.com/platform/frameworks/native/+/9cf89269c1/services/surfaceflinger/TimeStats/timestatsproto/TimeStatsHelper.cpp) | Retain original bucket counts and merge them before calculating percentiles. Preserve rounding and the capped tail instead of inventing precision. |

These are published examples, not a claim that every studio uses one universal
standard. We cannot instrument Riot's engine directly, so game context and frame
timing remain external observations.

## What is measured

The launcher starts a random-ID attempt before Android launch, checkpoints it
at readiness, once a minute and after samples, and finalizes it at stop/error.
The next launcher run recovers an unfinished checkpoint as `interrupted`.
Retries and out-of-order delivery keep the newest cumulative revision only.
The server retains each latest attempt for 30 days, without a transport IP.

The private dashboard reports:

- p50/p95/p99 presentation interval buckets, merged across sampled windows;
- a long-interval bucket rate per sampled minute;
- sampled slow-attempt fraction: over 25% of counts in buckets ≥34 ms;
- attempts, ready count, launch failures, cancellations, runtime errors,
  game exits of unknown intent, interrupted and still-open attempts;
- ready-time p95, coverage/missing/background counts, maximum sampled emulator
  RSS, serious/critical thermal checks and collector wall-time duty.

The frame histogram has 85 noncumulative entries: labels 0…34 by 1 ms, 36…50 by
2, 54…150 by 4, and 200…1000 by 50. AOSP rounds integer durations up to the next
label; the ≥102 ms bucket therefore includes 99–102 ms intervals and is only an
approximation of >100 ms hitches. The last bucket caps long intervals; some
Android revisions split very long waits into multiple last-bucket counts. Neither
percentiles nor the bucket rate quantify exact freezes. No-frame windows are
missing observations, so an unrecovered stall can be underrepresented.

Slow fractions require a terminal attempt and at least 5 windows, 10 measured
seconds and 300 counts **within that scene/stage/age context**. Lobby, unknown,
warmup and missing data never become healthy gameplay. Reportable cohorts need
at least 5 attempts; that is a display floor, not statistical significance.
The sampling interval can make eligible slow-attempt counts much smaller than
all attempts. Inspect this denominator before interpreting the fraction.

## Comparison rules

Tables hold exact Mac model, OS, physical RAM/CPU count, edition, APK version and
hash, resolution/density, effects, UI scale, guest CPU/RAM, profile hash and
collector constant. Rows identify launcher build, bundled runtime revision and
observed cache state. Unknown exposure stays unknown. Profile changes produce
separate tables; they cannot support a same-quality performance claim.

Scene labels require matching endpoints before and after a short sample. Stages
1–3 are early and 4+ late; this does not mean late PvP in Tocker's Trials. Session
age excludes launch-to-ready: first minute is warmup, then early until 20 minutes,
then sustained. The language classifier is English/Russian; unclear UI is unknown.
Transitions inside a window, match boundaries, game mode, quality changes made
inside the game and downloaded Riot content are not identified.

There is no persistent player ID. Attempts from the same player are not
independent people. This first dashboard provides descriptive, observational
comparisons. It does not compute causal uplift, confidence intervals, retention
per player, automated experiment decisions or remote rollout assignments.

## Rollout and evaluation plan

1. Deploy API compatibility and the 32 KiB proxy limit, then the privacy text,
   then the launcher with a renewed notice stating that performance is collected
   for everyone. Performance events carry no consent assertion. Optional
   completed-session diagnostics retain their separate consent checks.
2. Ship instrumentation first. Collect a baseline over a complete weekly cycle
   and until important hardware/context strata have useful coverage. Audit
   overhead, missing/unknown rate and the eligible denominator. A calendar week
   alone does not make the sample sufficient.
3. Predeclare the target strata, primary metric (for example combat p95),
   minimum practically useful change, and guardrails (launch reliability,
   long-interval rate, memory and thermal checks). Derive sample requirements
   from baseline variance; do not invent an industry-wide session count.
4. Change one runtime optimization at a time on a controlled preview cohort.
   Verify its runtime hash and actual activation. Prefer concurrent randomized
   assignment in a later experiment layer; current version comparisons cannot
   remove cohort selection or calendar effects. Keep the previous runtime
   available through the existing release process.
5. Expand only when the agreed quality and reliability checks pass across target
   configurations. If a cohort is small, coverage changes, APK/settings differ,
   or only the aggregate improves, record the result as inconclusive and collect
   more data. Do not use frames as independent statistical observations.

No release or remote rollout was performed by this implementation task.

## Validation record

The Android 16 local probe used a separate headless read-only AVD, with no game
interaction beyond launching TFT. At 1920×1080, two screenshots were classified
as `patch_available` (uploaded scene would be `unknown`). The 2.387-second
TimeStats probe, including setup, yielded 122 additional counts in the exact TFT
SurfaceView histogram. Screenshot plus classification took 1.631 seconds before
and 0.962 seconds after. Images stayed in pipes; only counts, dimensions and
coarse labels were inspected. The probe emulator was shut down afterward.

This verifies the data path and illustrates substantial adaptive backoff; it is
not a gameplay benchmark or an overhead comparison with collection disabled.
Gameplay classification accuracy and impact on sustained play still require a
preview baseline. The collector keeps its observation window outside screenshot
classification work, pauses in the background, uses bounded subprocess output
and timeouts. Collection and queued performance retries continue when optional
diagnostics are declined; only optional completed-session rows stop.

Automated checks cover Swift/API wire agreement, layer selection and counter
resets, scene transitions, failed launches, checkpoint recovery, stale ACKs,
collection/delivery/recovery with granted, denied, unknown and outdated choices,
nested unknown fields, histogram aggregation,
cohort suppression, storage retention/capacity and symlink rejection.

Validation passed: `scripts/test-mactician.command` (fixtures, Swift unit tests
and full launcher typecheck), classifier build/self-test, shared contract hash
verification; API Go 1.25.0 tests, race tests and vet; website typecheck, lint and
production build. The performance dashboard was rendered and visually checked
with explicitly labelled synthetic fixture data. Release signing/notarization
and production collection were not exercised. Website design primitives and
global styles were not changed.

## Loss diagnosis baseline (2026-09-11 implementation)

The recovery plan is in [performance-telemetry-recovery-plan.md](performance-telemetry-recovery-plan.md).
Diagnostic v1 explains the existing `screen-bracket-v1` labels without changing
OCR passes, context rules or sampling duty policy. Requested language is recorded
at attempt creation; it is not an inferred language or a claim about OCR support.
Frame failures, endpoint results and successful-window context have separate
cumulative denominators. Coarse states and partial signals survive failed scene
classification. Wall-time buckets cover screencap, classifier, TimeStats,
before/after gaps, cycle and foreground start intervals; intervals may include
background time. Before gap starts at screencap invocation, not a guest timestamp.

The dashboard shows collection quality before FPS, hides unclassified FPS from
gameplay tables, and separates descriptive samples from matched variants. Exact
comparison configurations include the classifier and diagnostic implementation.
The API accepts old checkpoints and prevents diagnostic identity/counter rewrites.
Deploy API/privacy compatibility first, then the diagnostic launcher. A field
baseline and sustained gameplay overhead measurement remain rollout checks;
local fixture verification alone cannot establish gameplay classification accuracy.

Diagnostics v2 additionally read a bounded tail of the game log locally in
memory. Only allowlisted lifecycle/GC-departure categories, event-age buckets,
read outcomes and timing counts are sent. Raw log text, identifiers, tokens and
event timestamps are never saved or uploaded. These shadow observations do not
change frame labels or assert the current stage/phase. They are standard
performance collection, with the same queue, retention and cohort suppression.

## Log context (2026-09-21 implementation)

New diagnostics v3 replace performance screenshots/OCR with two bounded log
reads around the frame window. They classify recent lobby, matchmaking,
match-starting or match activity; they do not infer current combat/planning or
numeric rounds from GC departures. Recent activity has descriptive frame
statistics and separate coverage counts, without gameplay eligibility. Historical
screenshot clients keep their original labels and classifier identity.

See [implementation and validation status](game-log-context.md). Swift tests and
typecheck, shared contracts, API tests/vet and the website lint/typecheck/build
pass. The report was visually checked with synthetic data. Live-match accuracy
and collection impact have not yet been verified; API compatibility must precede
launcher distribution. The owner-reported game-update delay and hosting outage
confound the earlier field snapshot and must not be treated as client regressions.
