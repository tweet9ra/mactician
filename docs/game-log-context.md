# Log-based collection context

The implementation replaces expensive screenshot/OCR brackets in the performance
collector with two bounded log reads. It recognizes recent lobby, matchmaking,
match-starting and in-match activity independently of language or resolution.
It does not manufacture a current planning/combat phase or numeric stage/round
from conditional garbage-collection departures.

Implementation: `GameLogObservation.bracket`, `PerformanceCollector`, diagnostics
v3 and `game-log-bracket-v1`. The matching API accepts both old and new contracts;
new coarse contexts have their own report columns. Recent match activity can show
descriptive frame measurements but never becomes a matched gameplay comparison or
a qualifying slow-session observation. See the
[contract](telemetry-contract/performance-diagnostics.md#log-based-context-diagnostics-v3).

## Validation

- Parser checks cover stale/future/pre-process records, missing logs, process
  replacement, rotation, truncation, backward/long clock gaps, context changes,
  unknown lifecycle enums and near-simultaneous lifecycle fields.
- Both scheduled and skipped-GC message formats are present in the owner's
  installed TFT `18.2-5492233` binary. Format presence alone does not establish
  emission frequency or coverage in an ordinary match.
- The shared v3 fixture round-trips through Swift and Go. API checks reject
  fabricated phase/round labels, mismatched contexts and missing boundary reads.
  Legacy fixtures retain their exact wire identities.
- The read-only local probe can exercise the same parser and bracket while an
  unmodified released client is running:

  ```sh
  python3 scripts/probe-tft-game-log.py --bracket --samples 12 --interval 5
  ```

  The probe waits two seconds between boundaries. It does not enable TimeStats,
  take screenshots, change game settings, send telemetry or control the game.
  It prints only bounded contexts/reasons and wall times. A single-read probe
  without `--bracket` prints the context and bounded source observations.

Parser/unit coverage is not a live-match accuracy result. A complete ordinary
match against a labelled timeline remains necessary before claiming phase
accuracy, a field unknown percentage or an FPS improvement.

Mactician 1.2.5 (build 54) enables this collector. Its compatible API and privacy
page are deployed before the launcher update. Release verification includes the
full Swift tests/typecheck, repository and shared-contract checks, Go 1.25.0
tests with the race detector and vet, and website typecheck/lint/build. Game APKs,
runtime scripts and graphics profiles remain identical to 1.2.4. Field data from
this collector must be kept separate from the earlier screen classifier.

## Incident context supplied September 21

The owner reported a one-to-two-day delay publishing a required TFT update, during
which users could not reach matches, and over a day of website-server downtime
due to a hosting outage. Exact boundaries are not yet established.
Those periods confound readiness, context mix and delivery. The earlier package
association is not evidence of a client regression; an absence of delivered
measurements during downtime is not evidence of zero usage or good performance.
