# Research log

This edited log preserves the useful technical chronology and negative results.
Benchmark tables and acceptance rules are summarized separately in
[Benchmarks](benchmarks.md).

## Contents

1. [Compatibility problem](#compatibility-problem)
2. [Working GLES 3.2 path](#working-gles-32-path)
3. [Native window and host scheduling](#native-window-and-host-scheduling)
4. [Resolution, memory, and CPU](#resolution-memory-and-cpu)
5. [Device profile and overlays](#device-profile-and-overlays)
6. [First-use stalls and root scheduling](#first-use-stalls-and-root-scheduling)
7. [Input and game-owned latency](#input-and-game-owned-latency)
8. [Transport and renderer experiments](#transport-and-renderer-experiments)
9. [Login WebView failures](#login-webview-failures)
10. [Fixed-stage campaign](#fixed-stage-campaign)
11. [Historical and rejected findings](#historical-and-rejected-findings)
12. [September buffer-view cache](#september-buffer-view-cache)
13. [TFT 18.6 match-entry crash](#tft-186-match-entry-crash)

## Compatibility problem

The initial Android 12 environments installed the unmodified TFT PBE package but
exposed only OpenGL ES 2/3/3.1. TFT PBE `18.1-5212127` requires ES 3.2 or newer,
so installation success did not imply a runnable client. Generic Vulkan flags
did not make the Shipping build select a compatible GLES context.

The small [`angle-egl-probe.cpp`](../artifacts/angle-egl-probe.cpp) probe and
early runtime observations established the graphics-version boundary. Raw crash
tombstones are no longer retained in the public repository.

## Working GLES 3.2 path

Android Emulator 37.1.11 was configured to select ANGLE for the TFT package and
enable `exposeNonConformantExtensionsAndVersions:exposeES32ForTesting`. TFT then
observed GLES 3.2 while ANGLE rendered through Vulkan and the emulator mapped
gfxstream/MoltenVK to Metal. The game reached UI, downloaded content,
authenticated, and entered a match, validating more than process startup.

The lower-level renderer entrypoint is
[`run-tft-angle-opengl.command`](../run-tft-angle-opengl.command); the canonical
wrapper is [`run-tft-best-verified.command`](../run-tft-best-verified.command).

## Native window and host scheduling

The original scrcpy display path used software video encoders inside the guest.
That competed with TFT and shader workers and introduced random freezes.
Right-click also mapped to Android Back, which looked like a crash but was a
normal pause/focus loss. Moving to the Emulator's native window removed the
encode path and preserved normal mouse behavior.

zsh's default `BG_NICE` silently started background-orchestrated QEMU at nice 5.
All launch wrappers now disable `BG_NICE`, preserving normal nice 0 host
scheduling.

## Resolution, memory, and CPU

Stretching a 1280×720 emulator surface improved neither source detail nor frame
rate. The selected device profile forces 100% screen percentage and disables
dynamic resolution. A controlled stage-1-5 switch measured 31.3 FPS at
2560×1440 versus 30.5 at 1600×900, despite 2.56× source pixels. This was a
CPU/RHI-bound scene, not proof that resolution is universally free.

Seven guest CPUs left capacity outside TFT's observed five-core PSO mask. Later
samples showed roughly 4.5 of seven guest CPUs idle and only about 1.3 CPUs used
by TFT, so an eighth vCPU was not justified. Guest memory also retained several
GiB of available/cache memory; indiscriminately raising RAM could increase host
pressure without addressing the measured bottleneck.

## Device profile and overlays

TFT selected generic low-performance fragments for the virtual Apple GPU. The
verified profile raised screen percentage, disabled dynamic resolution, enabled
mobile GPU-scene textures, bypassed the queued RHI command path, and retained
FXAA4/aniso8. Direct Unreal Vulkan remained disabled; Vulkan is used below
ANGLE.

An ordinary copied `DeviceProfiles.ini` was consumed after one TFT start. A
later process restart fell back to 1280×720 buffers inside a 2560×1440 display.
The launcher now checksum-verifies and bind-mounts the profile transactionally
for the whole AVD session. The installed APK remains intact, and cleanup restores
or removes every temporary mount.

Profiles are under
[`artifacts/tft-pbe-18.1-5212127-angle-opengl/`](../artifacts/tft-pbe-18.1-5212127-angle-opengl/).

## First-use stalls and root scheduling

Unreal logs and behavior separated first-use shader/PSO stalls from steady
frame rate. A broad prewarm that forced `r.PSOPrecaching=1` reproducibly crashed
inside OpenGL program-cache initialization and was rejected without deleting
the persistent program-binary cache.

Four `psoprogramservice` processes were restricted to guest CPUs 0–2 even
though TFT could use 0–6. A separate official Android 36 Google APIs `userdebug`
AVD enabled supported, visible `adb root`. The launcher kept every PSO-service
thread on CPUs 0–6 and raised only their 28 `ANGLE-Worker` threads from nice 19
to nice 0. The user observed that large first-use effect stalls disappeared,
although steady match rendering remained heavy.

TFT PBE `18.1-5300314` later changed the inherited Android profile from four
remote OpenGL program compiler services to zero. The first launch therefore
recreated the update-specific program-binary cache, and a later match still
started with only 341 cached programs / 20.8 MB versus 2,353 programs / 106.4 MB
on the previous build. Unreal reported both `Remote PSO services disabled` and
`Ignoring precache PSO, external compiler not active`; the cache grew to 34 MB
during that match. The launcher profiles now explicitly request the previously
verified four OpenGL compiler services instead of inheriting this patch-varying
game default.

[`scripts/watch-root-pso.command`](../scripts/watch-root-pso.command) reapplies
the setting every ten seconds because Android task profiles can restore the old
affinity. One-second polling was rejected as unnecessary ADB/thread-scan noise.

## Input and game-owned latency

Android input channels were responsive, with no pending event and empty inbound
and command queues. A later drag capture delivered touch reports around
119–120 Hz. Renderer queue experiments therefore targeted click-to-next-frame
latency rather than replacing mouse injection.

The stage-1-2 input A/B rejected no-frame-ahead (-21.9% FPS) and synchronous
submit (-10.3%). Disabling async composition stayed within the original 10%
budget but cost 7.6% without a proven visible improvement. Explicit native
swapchain was already enabled by default.

An exact shop toggle showed immediate button response followed by a roughly
250 ms panel transition while frames continued. Touchscreen, stylus, rapid
double-tap, and zero Android animation scales did not remove it. Static evidence
points to a cooked CommonUI animated switcher, so modifying signed game assets
or trading away FPS was rejected.

The tools are [`scripts/run-input-latency-experiment.command`](../scripts/run-input-latency-experiment.command),
[`scripts/capture-input-latency.command`](../scripts/capture-input-latency.command),
and [`scripts/compare-input-latency.command`](../scripts/compare-input-latency.command).

## Transport and renderer experiments

The early ASG comparison mixed menu and match scenes and is historical. A later
exact stage-1-1 A/B measured 40.1 FPS / 34.85 ms p95 on ASG versus 29.6 FPS /
49.75 ms p95 on pipe. ASG was selected through the reversible
[`scripts/run-asg-experiment.command`](../scripts/run-asg-experiment.command).

Raising the ASG write buffer above 1 MiB crashed startup with
`External address size too small`; 1 MiB/4 KiB remains the limit. MSAA2 blacked
out the 3D pass. Material quality 1 was neutral/noisier. RHIThread profiling
moved the dominant evidence toward guest-to-host ASG writes after GPU-scene
textures removed the earlier buffer-view hotspot.

MoltenVK async submission and 64 active Metal command buffers were retained.
The 128-buffer candidate produced one strong run but failed cold and sustained
reproduction; see
[`run-tft-mvk128-experimental.command`](../run-tft-mvk128-experimental.command).
The isolated active-consumer host patch produced a severe same-scene regression
and now requires explicit forensic opt-in.

## Login WebView failures

The official Riot WebView originally deadlocked when a field interaction caused
Skia Vulkan rendering to wait through gfxstream. Selecting Android HWUI's Skia
OpenGL renderer avoided that WebView path without disabling Vulkan underneath
TFT's ANGLE SurfaceView.

A separate repaint issue made two fields disappear while their DOM geometry and
hit boxes remained valid. Both wrappers retained completed 800 ms
`fill: forwards` animations. Launcher 1.6.8 added a scoped service that, only
while the exact official login activity is top-resumed, connects through a
temporary loopback ADB forward, cancels those two animations, verifies the
expected fields/wrappers, and removes the forward. It generates no focus or
input and reads no credentials or form values.

The optional [`scripts/login-tft-from-keychain.command`](../scripts/login-tft-from-keychain.command)
is separate automation. It performs a no-secret preflight, refuses visible
CAPTCHA/MFA, then reads a local Keychain item and submits the official form
through native DOM setters. Credentials and Android login state are never part
of the repository.

The September 8 session-persistence investigation found a separate cause of
repeated sign-in: TFT 18.1-5423749 starts Riot with `persistLogin: false`.
The reflected Unreal Config property belongs to
`/Script/OnlineSubsystemRiot.RGIOPRiotGamesApiSettings` in `Engine.ini`.
The launcher now enables `bPersistLogin=True` before starting TFT, alongside
the existing UI-scale configuration. Riot continues to own and encrypt its
session; the launcher does not store passwords or copy authentication files.
On a cloned AVD, the runtime configuration changed to `persistLogin: true`,
and a real signed-in session survived an application force-stop and two cold
Android boots without credential entry. See the sanitized
[`validation artifact`](../artifacts/riot-session-persistence-validation-20260908.json).

## Fixed-stage campaign

On 2026-08-05/06, the autonomous harness replaced ad-hoc screens with fresh
Trial stages 1-2, 1-5, and 1-8, semantic before/after gates, active hashes, and
verified rollback. Three controls averaged 40.60/36.03/27.83 FPS. Submit thread,
shader prewarm, submit+prewarm, and upstream ASG failed promotion.

The first bounded navigation loop used XP-first actions, no rerolls, one shop
purchase pass, one bench deployment pass, and one early item pass. It reduced
normal preparation to 20–22 seconds and recorded every stage in
`planning-events.jsonl`.

On 2026-08-09/10, the loop was replaced by combat-overlapped shop analysis,
one expensive-card purchase, batched reward waypoints and XP taps, a single
evidence-driven board placement, and a one-time carry item batch. Normal
preparation now takes 1–3 seconds; representative complete runs averaged
1.9–2.1 seconds with zero rerolls. Choice screens are classified explicitly,
early deaths use `PLAY AGAIN` in the same emulator, and valid stage captures
survive a replay. A stale Trial is surrendered before a fresh 1-1. These changes
make short 1-5 screens practical and reserve 1-8 for promising candidates.

The final transport screens used the selected 67% profile and 16 KiB ASG write
step. `VirtioGpuNativeSync` regressed stage 1-5 to 37.5 FPS, while
`VirtioGpuNext` was neutral at 42.4 FPS versus the 43.0 FPS wrapper integration
control. Disabling Vulkan batched descriptor updates also regressed to 40.3
FPS. A heavier-scene hypothesis that forced skeletal animation updates every
second frame with interpolation measured 39.4/33.1 FPS at stages 1-5/1-8 and
worsened the 1-8 tail to 37.01 ms p95 and 47.11 ms p99. None was promoted.

The same campaign isolated scene work from transport work. At 67% 3D scale,
aggressive effect/particle limits plus shorter view/mesh LOD retained 32.0 and
35.6 FPS in two complete 1-8 runs. A paired ASG sweep selected a 16 KiB write
step: two full runs averaged 41.45 FPS at 1-5 and 34.60 at 1-8 versus a new 4
KiB control at 38.0/32.8. Guest profiling supported the mechanism: total
samples fell from 17,000 to 14,408, `writew` from 13.31% to 12.69%, speculative
reads from 3.71% to 2.50%, and ring waits from 3.29% to 2.92%. The 8/32 KiB
screens, 64/128 KiB data rings, 2/4 ms flush variants, 50% resolution, and
isolated or extreme effect/LOD profiles did not pass promotion gates. A 512 KiB
ASG write buffer failed twice during startup and was rolled back; 1 MiB remains
required by this emulator build.

Disabling emulator audio also screened neutral/slower at 42.1 FPS versus the
43.0 FPS Performance Max integration run, so AudioMixer sampling weight was not
treated as proof of a frame-time bottleneck.

The historical stage-1-8 profiles were re-aggregated with a versioned
simpleperf parser. The selected 16 KiB/on-demand control spent 31.49% of sampled
CPU on RHIThread and 16.44% in guest transport symbols. Inline submission raised
those shares to 37.50%/19.78% and regressed FPS by 9.59%. A 32 KiB step retained
33.93%/18.52%; one faster 1-8 capture did not overturn its failed broader
screen. This strengthens the boundary diagnosis without claiming late-PvP
coverage or promoting a new setting.

On 2026-08-15, the harness gained a passive late-PvP observer. It targets stages
4+ in player-combat rounds, excludes carousel and PvE rounds, sends no input,
and accepts a pacing window only when the before/after stage and combat phase
agree. Its first accepted window is followed, never overlapped, by a bounded
guest profile with a second semantic gate. The raw simpleperf data and SHA-256
are retained so caller-inclusive attribution remains possible after capture;
the earlier flattened reports could expose leaf costs but not reliably assign
transport leaves back to a stripped Unreal caller. This addresses the remaining
evidence gap directly: stage 1-8 is not substituted for the user's roughly
15 FPS late-game report.

The observer's session summary now distinguishes pacing acceptance from CPU
profile coverage. It counts attempted, accepted, and raw-callgraph profiles,
while explicitly keeping profiling out of the FPS promotion gate. A negative
fixture makes `adb pull` fail after a successful record/report and verifies that
the pacing sample survives, the profile is rejected without a fabricated hash,
no partial raw file remains, and the guest temporary file is still cleaned up.
Another fixture changes the active profile only after sampling: the raw file is
preserved for diagnosis, but its attribution is rejected because the
PID/hash/single-mount bracket no longer passes.

The late-PvP profile now brackets simpleperf with per-thread procfs scheduler
snapshots. A machine-readable comparison reports CPU time, actual scheduled
runtime, run-queue delay, timeslices, priority/nice, and the final wait channel,
with named aggregates for GameThread, RHIThread, RenderThread, AudioMixer,
TaskGraph, and PSO workers. This closes an ambiguity in the earlier 31.49%
RHIThread result: the next real heavy capture can show whether that thread is
doing work or losing time waiting to be scheduled. The fixture covers thread
creation, role mapping, tick conversion, and nonnegative delta filtering.

A live 120-thread login-screen validation then matched every before/after task.
It also ruled out a scheduler-priority candidate: RHIThread, GameThread,
RenderThread, and active TaskGraph workers already ran at priority 10 / nice
−10. The recorded run-queue ratios are deliberately not generalized to combat;
their value is proving the collector works before the next authenticated match.

Static inspection found one more Riot-authored CPU hypothesis with unusually
direct intent: `tft.EnableDragSubsystemTicklessMode` is compiled false and its
help says it avoids ticking the drag subsystem every frame. A one-line profile
was queued. It cannot be promoted without unit, item, bench, sell, and idle
transition checks, because a small steady GameThread win would not justify
breaking a core interaction path.

Its cold boot logged a direct `false -> 1` DeviceProfile transition. The
process remained alive, RSS matched the surrounding cold boots, and Android
reported neither crash-buffer output nor a fresh tombstone. This proves the
flag was not already enabled and is startup-safe, while deliberately leaving
drag semantics and combat performance unresolved.

The same pass added a selectable Maximum FPS app preset, explicitly restored
four remote OpenGL compiler services for the current Riot build, and prepared
single-factor screens around the selected stack. Four exercise ANGLE
buffer/barrier behavior and one isolates direct OpenGL UBO writes. They
cold-booted the game to the login UI and completed verified
rollback. Riot authentication was unavailable, so they remain unmeasured
candidates and are not promotion evidence. A focused campaign can select exact
candidate IDs with `--queue id,id,...`; the queue is checkpointed and cannot be
silently changed on resume.

An attested Android Settings transport screen then interleaved four cold
controls with those ANGLE flags. The 12-round control means ranged from 6583.39
to 6635.68 ms. `preferCPUForBufferSubData` repeated at 6604.20/6635.09 ms and
disabling buffer barrier events at 6609.95/6635.16 ms; both averages were about
0.1% slower than the 6612.87 ms control mean. Aggregate barriers and disabling
image events also stayed inside control noise. A separate 20-round pair found
no cost from the launcher's two one-hertz ADB polls, and six versus seven vCPUs
was mixed and below one percent. No setting was promoted from these screens.

An Android GLES microbenchmark replaced the UI proxy for buffer-path questions.
It ran in a normal Activity with guest ANGLE and Vulkan ranchu mappings
attested from `/proc/self/maps`, used 16 KiB updates, and discarded seven
warmup rounds. Two cold runs rejected `preferCPUForBufferSubData` at +2.05%
mean median latency. Aggregate barriers were neutral (+0.20%); disabling buffer
barrier events was unstable and worsened both p95 samples. All samples had zero
GL errors and verified rollback. These results isolate transport behavior and
are not substituted for late-PvP FPS. The complete curated result is
[`artifacts/android-gles-buffer-stress-screen-20260815.json`](../artifacts/android-gles-buffer-stress-screen-20260815.json).

A draw-heavy GLES follow-up used 256 UBO-backed triangle draws per frame,
ping-pong render targets, texture sampling, and explicit buffer/image barriers.
Eleven interleaved cold boots showed that CPU buffer copy was 3.71% slower on
median and 9.15% worse on p95. Disabling buffer-barrier events had a 3.68% p95
regression. Aggregate barriers and disabling image-barrier events stayed below
the 3% promotion threshold, with the latter also worsening p95. No ANGLE flag
was promoted. The curated run set is
[`artifacts/android-gles-draw-stress-screen-20260815.json`](../artifacts/android-gles-draw-stress-screen-20260815.json).

Static UTF-16LE CVar extraction from the current Riot `libUnreal.so` confirmed
that the build contains `fx.Budget.*`, `fx.Niagara.UseGlobalFXBudget`,
`fx.Niagara.Scalability.GlobalBudgetCulling`, and the game-specific
`tft.Tick.RelevancyEnabled`. A two-millisecond adaptive FX-budget profile was
therefore added as a seventh isolated candidate and cold-booted successfully
with verified rollback. It remains unpromoted until a matched late-PvP A/B
also proves that important spell cues remain visible.

Direct runtime queries failed closed. The original per-CVar `-ExecCmds` list
reached the Unreal command line but logged no responses. Two narrower
`DumpCVars` follow-ups then requested the relevant FX, Niagara, animation,
dynamic-mesh, and Riot-tick prefixes: one to CSV and one to `TFT.log`. Both
command lines were present, but neither produced dump output. The temporary
extension was removed, and documented engine defaults remain hypotheses rather
than claimed runtime values.

A later startup audit used `TFT.log`'s own `LogConfig` and
`LogDeviceProfileManager` transition records. Riot already enables its
animation budget (`a.Budget.Enabled=1`), reduces it to 1.5 ms at low view
quality, disables cloth/AnimDynamics, and disables both HZB and occlusion
queries. The no-occlusion screen was removed as a proven no-op. The audit also
showed that low effects quality first selects
`r.EmitterSpawnRateScale=0.125`, after which Performance Max raises it to
`0.5`. A 0.125 candidate and a separate parallel dynamic-mesh candidate were
added for a future matched late-PvP visual/performance gate; neither is
promoted.

The audit also exposed a later saved-settings pass. Although Performance Max
selects `sg.*=0`, saved quality level 2 reapplies higher unpinned values after
the DeviceProfile: animation budget 1.5→1.85 ms, upscaler 1→2, texture-streaming
batch 5→10, translucency volume 24→48, foliage/grass 0.5→1.0, plus SSS/SSGI and
anisotropic materials. A new isolated profile pins 14 values to the exact Riot
low-scalability values. Its cold boot produced 14/14 exact DeviceProfile push
records and 13 explicit lower-priority rejections; grass density had no later
override record. It then completed verified rollback. This proves configuration
precedence and boot safety, not an FPS gain; it awaits the same late-PvP A/B gate
as the other Unreal-side candidates.

Epic documents 1.0 ms as the low-scalability example for the Animation Budget
Allocator, which dynamically lowers skeletal-mesh update work by significance.
Because Riot already enables that allocator, a new one-factor profile pins only
`a.Budget.BudgetMs=1.0`. Its cold boot logged the 1.5→1.0 DeviceProfile push and
kept 1.0 when saved quality later attempted 1.85. This is a more targeted
late-board CPU hypothesis than forced URO, but still needs matched late-PvP FPS
and unit-animation legibility gates.

The passive workflow now has a machine-readable matched-session summarizer. It
compares only exact late stage/round strata with matching host power, thermal,
display, renderer, and guest-driver conditions; common strata receive equal
weight. The screen requires two contributing sessions per variant and keeps
promotion disabled even when its 3% FPS/tail-latency gates pass, because board
and opponent composition cannot be held constant across matches. This removes
the earlier temptation to average unrelated late fights while preserving a
usable path for the next authenticated control/candidate collection.

A direct AArch64 read of the exact stripped Riot `libUnreal.so` avoided another
set of no-op boots. The compiled defaults already enable actor pooling, Chrono
pooling, Chrono-handler reuse, managed-tick relevancy filtering, and
phase-triggered GC; they already leave Chrono's single-thread sync disabled.
Actor-pool warming is compiled off. A one-factor profile now enables only that
flag and is held behind startup, memory, and matched late-PvP hitch-tail gates.
This is a spawn-stutter hypothesis, not a credited FPS improvement.

One candidate/control cold-boot pair cleared the first two gates. The candidate
startup log attested the exact one-line CVar push. Three post-ready samples per
variant found only −0.006% RSS and −0.026% PSS differences; boot time was also
inside run noise. Actor-pool warming therefore remains eligible for a real
late-PvP hitch-tail screen, but is neither promoted nor credited with FPS.

A provenance check found that the first particle audit had decoded addresses
from a `libUnreal.so` whose hash did not match the library mapped by the live
game. The names happened to be identical, but code and data offsets were not.
The audit was repeated against the hash-verified live image and now shows
`FX.AllowAsyncTick=1` and `FX.BatchAsync=32`. Direct reads from the control
process returned the same values. The apparent `FX.AllowAsyncTick=1` candidate
was therefore a no-op and has been removed from the campaign queue.

Its previous crash-free cold boot remains useful as a warning about method:
the DeviceProfile log proved that the line was pushed, not that the effective
value changed. The startup artifact now records the no-op resolution. The same
live-storage method independently confirmed drag tickless at zero in control,
so that candidate remains a real one-factor change rather than being discarded
by association.

A second live read after booting the drag profile returned one from the same
hash-matched storage while the particle values stayed at their control values.
This proves runtime isolation (`0 -> 1`) beyond startup logging. Promotion is
still blocked on board/bench/item drag correctness and matched late-PvP data.

The corrected library also showed that Niagara's main async tick, async
sim-cache tick, GPU-tick batching, world object pool, component pool, and legacy
particle pool are already live at one. Mesh draw dynamic instancing and parallel
pass setup are compiled on as well. These enablement ideas were rejected as
no-ops. One supported but unproven scheduling mode remains: changing Niagara
`TickBatchMode` from 1 to 0 schedules the final batch as a task rather than
running it inline. A one-factor profile was queued behind cold-start,
effect-correctness, task-overhead, and matched late-PvP frame-tail gates.

That candidate passed the non-combat gates: 17.65-second cold boot, empty crash
buffer, unchanged tombstone inventory, and login-screen RSS/PSS within roughly
1.2/0.8 MiB of a nearby control. Startup logging and a hash-checked live memory
read both proved mode zero while adjacent async/batching controls stayed at one.
The experiment remains unpromoted because login contains no representative
Niagara batches and cannot reveal task overhead or missing/late combat effects.

A broader late-PvP threading audit then decoded only the shipped, hash-matched
binary rather than guessing at generic Unreal switches. Audio batching is
already on with a batch size of 128. Parallel animation evaluation, update,
interpolation, and physics blending are already on; forcing parallel animation
would bypass asset and project opt-outs. Async component ticks and multithreaded
mesh-command caching are also enabled. The disabled batched/concurrent core tick
queue, async dispatch, and async cleanup switches were deliberately not queued:
their ordering and task-overhead risk needs attribution from a real heavy-fight
trace, which the expired login cannot supply.

Two narrow non-noop scheduling experiments survived that filter. One moves
eligible particle-system async scheduling earlier in the frame. The other raises
Niagara system-simulation task batches from four to eight instances, testing
whether fewer tasks improve the GameThread/RHIThread tail in effect-heavy fights.
Both cold-booted in about 17.8 seconds, used no swap, produced no crash evidence
or fresh tombstone, and stayed within the surrounding Performance Max login
memory range. Startup logs attested the exact `0 -> 1` and `4 -> 8` transitions;
a hash-checked live read independently returned batch size eight with adjacent
async controls unchanged. They remain unpromoted because neither cold boot nor
login measures particle workload, timing, legibility, or TFT FPS.

The matched late-PvP summarizer was also tightened before any new authenticated
data arrives. A variant must now contribute exactly one known DeviceProfile
SHA-256 in every common stratum, and control/candidate hashes must differ. A
fixture that reuses a candidate label for two profile binaries is explicitly
rejected. This prevents a resumed or manually edited experiment from producing
a convincing average out of different configurations.

The observer now also accepts a campaign candidate ID and resolves its variant,
profile path, and SHA-256 directly from the manifest. `--print-selection`
attests that mapping without touching ADB, and unknown IDs fail early. This
removes a manual profile/label mismatch from the next authenticated session.
The same manifest initially stored a six-item, hash-pinned late-PvP priority
queue, which the observer can print without contacting the emulator. It orders
work by existing attribution and synthetic/cold evidence rather than manifest
position; the animation-budget candidate added below later expands it to seven.

The same binary audit revisited the largest named stage-1-8 CPU consumer,
RHIThread. Performance Max currently forces `r.RHICmdBypass=1`, although the
compiled default is zero and OpenGL RHI threading, parallel translation, and
cached mesh draw commands are already enabled. The compiled translate batch is
256 commands and the minimum parallel command-list threshold is 64 draws. An
isolated profile now restores bypass zero to test whether effect-heavy player
combat can distribute command construction better. Its cold control pair was
memory/startup-neutral and crash-free, so it remains queued. Login cannot
decide the tradeoff: the next authenticated screen must compare RHIThread and
RenderThread work plus FPS/p95/p99 under the same late-PvP strata.

A neighboring renderer audit found one more bounded scheduling threshold.
`r.GPUScene.ParallelUpdate` is compiled at 2,048 updated items; the shipped help
defines positive values as the item-count threshold for parallel primitive and
instance updates. Lowering only that threshold to 512 passed a consecutive cold
pair with essentially identical memory, no swap, no crash, and no new
tombstone. Startup attested `2048 -> 512`. Broader enablement was not queued:
Niagara GDME, visibility task scheduling, and translucent rendering are already
parallel. The threshold remains unpromoted because an expired-login screen
cannot supply a dense GPU Scene or any TFT FPS evidence.

The Riot-specific pass also closed four tempting dead ends. Delayed Chrono
start, median frame-alignment compensation, single reconstruction of a repeated
remote move, and transform preservation during an empty replicated-movement
blend are all compiled on. Their embedded help describes hitch/pacing or
movement-correctness behavior, but enabling them in a profile would be a no-op.
The exact defaults and constructor evidence were added to
[`artifacts/tft-runtime-boolean-default-audit-20260815.json`](../artifacts/tft-runtime-boolean-default-audit-20260815.json).

Finally, both generic visibility work-size controls were decoded as zero, which
their embedded help defines as automatic frustum-task and relevance-packet
sizing. Forcing a primitive count would replace engine adaptation without a
late trace. The remaining 256-primitive parallel-gather control applies only
when shadow-octree culling is disabled and is not justified for the low-shadow
profile. These were recorded as rejected fixed-threshold experiments rather
than added to the queue.

The adjacent GPU Scene allocation controls were likewise bounded. Light setup
is already asynchronous; grow-only allocation is a deprecated compatibility
mode that prevents buffers from shrinking; and the default negative tile size
avoids reserved-resource assumptions on Android/gfxstream. Raising the 256,000
byte pooled-upload ceiling would retain larger buffers, while the heavy proxy
does not attribute enough cost to GPU Scene allocation to justify that trade.
No allocation candidate was added.

An authentication-independent UBO microbenchmark then exercised four update
strategies on the attested guest ANGLE→Vulkan path. The 13-run campaign used
seven alternating `glBufferSubData` controls and two independent brackets per
candidate. Mapping and filling a whole aligned pool once per frame repeated a
large win in both blocks (−33.63% median, −30.54% p95 time per draw). Mapping
once per draw was mixed and below the promotion threshold; calling subdata and
rebinding a pool for every draw was catastrophically slower. The result moves
the already-isolated 16 MiB Unreal UBO-pool profile to the front of the next
authenticated late-PvP queue, but it is not promoted: the synthetic app cannot
prove Unreal's internal allocation path, game visual correctness, or TFT FPS.
The app source, runner, alternating-bracket summarizer, and curated result are
kept as hash-checked evidence.

The winning strategy was then repeated under higher synthetic draw density.
Alternating five-run screens at 512 and a bounded 1024 draws per frame produced
four more wins: the 512-draw blocks averaged −48.99% median / −48.08% p95 time
per draw, and the 1024-draw blocks averaged −53.13% / −52.44%. All retained
runs reported zero GLES errors. Together with the two original 256-draw blocks,
map-once wins six of six independent brackets. An earlier long 1024-draw
attempt produced no summary after the outer launcher watchdog closed the AVD
and is explicitly excluded. This improves hypothesis ranking only; it neither
measures TFT FPS nor proves Unreal path equivalence or combat visual
correctness. The curated result is
[`artifacts/android-gles-ubo-density-screen-20260815.json`](../artifacts/android-gles-ubo-density-screen-20260815.json).

The corresponding capacity audit found a much narrower synthetic footprint
than the candidate name suggests. With 16-byte alignment and a 32-byte stride,
the 256/512/1024-draw screens allocate only 8/16/32 KiB per synthetic frame.
Thus 16 MiB is 512× the largest measured working set. Exact-binary inspection
confirmed GL uniform-buffer allocation code and runtime storage confirmed the
configured capacity, but neither reveals the live late-PvP high-water mark.
The queue retains the candidate on strategy evidence while labelling capacity
`unsized_hypothesis`; no speculative 4 MiB profile was added. If 16 MiB first
wins authenticated combat tails and correctness gates, a later 4/8/16 MiB
ladder can find the smallest sufficient capacity. Evidence is in
[`artifacts/unreal-opengl-ubo-capacity-sizing-audit-20260815.json`](../artifacts/unreal-opengl-ubo-capacity-sizing-audit-20260815.json).

The three original simpleperf reports were also re-opened at their pinned
hashes. The Performance Max control's 31.49% RHIThread share contains 16.44%
transport leaves but only 1.60% stripped Unreal leaf offsets. Neither it nor
the inline and 32 KiB reports contains an exclusive row in the exact-binary
OpenGL buffer/UBO corridor. Because the reports are flattened, this cannot
exclude a UBO caller above a transport leaf; it does prevent relabelling all
RHIThread samples as UBO work. No candidate was promoted or demoted. The
late-PvP observer now pulls and hashes raw perf data so the next authenticated
capture preserves call chains. The bounded conclusion is in
[`artifacts/simpleperf-rhi-unreal-offset-audit-20260815.json`](../artifacts/simpleperf-rhi-unreal-offset-audit-20260815.json).

To isolate a possible ASG-specific artifact, the 512-draw five-run bracket was
repeated on stock `pipe` with the same OSFT/ANGLE flags and workload. Map-once
again won both blocks (−47.33% median / −50.18% p95 on average), bringing the
retained strategy record to eight wins in eight brackets. This supports a
transport-independent UBO update-cost hypothesis, but it is not a transport
benchmark: pipe and ASG ran in separate cold launches, so their absolute times
are not compared and the selected transport is unchanged. The cross-check is
[`artifacts/android-gles-ubo-transport-crosscheck-20260815.json`](../artifacts/android-gles-ubo-transport-crosscheck-20260815.json).

After the synthetic campaign, a cold stock launch recovered the interrupted
profile journal before starting TFT. The live stock process saw the original
base APK, no private `DeviceProfiles.ini`, zero base/profile bind mounts, the
stable profile over `pipe`, no transaction markers, and an empty crash buffer.
The intentional shutdown left zero ADB devices, emulator processes, or AVD
locks, while both persisted transport configs remained `pipe`. This final
rollback attestation is retained in
[`artifacts/stock-rollback-validation-20260815.json`](../artifacts/stock-rollback-validation-20260815.json).

The campaign entrypoint is
[`scripts/run-performance-campaign.command`](../scripts/run-performance-campaign.command);
candidates are declared in
[`scripts/performance-candidates.json`](../scripts/performance-candidates.json),
and the passive observer is
[`scripts/capture-late-pvp-session.command`](../scripts/capture-late-pvp-session.command).
The observer now fails closed unless the selected profile SHA-256 is also the
single live TFT `DeviceProfiles.ini` bind mount; successful session manifests
retain the PID, destination, mount count, and active hash. This closes the gap
between selecting a candidate on the host and measuring the profile that the
game process actually sees. Because a passive session may run for 90 minutes,
the observer repeats the PID, SHA-256, and single-mount check immediately before
and after every pacing window. One fixture swaps the active hash after the
initial preflight and proves collection stops before the frame helper; another
swaps it only after the helper returns and proves the written summary receives
no acceptance marker, never enters the aggregate, and cannot start profiling.
The matched-session summarizer independently requires that successful live
attestation in every manifest and rejects any capture whose profile hash differs
from the manifest, so hand-edited or legacy unattested directories cannot enter
an A/B result.
It also makes the reported game version and active base-APK SHA-256 part of the
exact stratum key. A negative fixture changes both fields in one otherwise
matching candidate session and proves that the round is not pooled across Riot
patches; captures missing either attestation are ineligible.
Host conditions are now bracketed as well: power source, the mode in the active
AC or battery section, and thermal state are sampled before and after each FPS
window. The summarizer admits only exact stable pairs and has a negative fixture
for a mid-window host-condition transition.

A final Riot-specific audio pass found two shipped but disabled controls:
playing music only for the current arena and restricting simultaneous ambient
sounds. Neither was queued. Both intentionally change audio presentation, and
the earlier full audio-off screen was neutral/slower; they should be revisited
only if a real late-PvP profile attributes material frame time or run-queue
delay to AudioMixer. Their exact defaults and constructor evidence are retained
in the Riot boolean-default audit.

The hash-pinned late-PvP priority queue now includes the existing isolated
`a.Budget.BudgetMs=1.0` profile immediately after the two RHI hypotheses. It is
more directly coupled to a dense late board than the remaining scheduling
experiments: Riot already enables the significance-aware allocator, while a
later saved-settings pass otherwise raises its low-quality budget to 1.85 ms.
This is prioritization only, not promotion; unit animation cadence and attack
or spell timing remain mandatory correctness gates.

A final skeletal-render hot-path audit ruled out another family of apparent
late-board wins. The shipped binary already enables local-bounds caching,
high-priority skinned ticks, asynchronous skin-buffer updates, cached skeletal
mesh draw commands, the parallel skeletal updater, and the SkeletalMesh render
command pipe. Its dynamic-data pool is also enabled with a 4 MiB budget.
Together with the already-proven parallel animation evaluation/update/
interpolation and physics blend defaults, these are no-op enablement ideas.
Raising the pool without live miss/allocation evidence would merely trade
retained memory for a hypothetical hitch reduction, so no candidate was added.
Exact registration/default evidence is in
[`artifacts/unreal-skeletal-hot-path-audit-20260815.json`](../artifacts/unreal-skeletal-hot-path-audit-20260815.json).

The uniform-expression and render-command-pipe follow-up also rejected only
no-ops: the three audited material-cache paths, all declared render-command
pipes, and Niagara dynamic-data piping are already enabled. The
Vulkan-specific upload control is enabled but is not an OpenGL RHI switch. A
runtime lookup for `r.UniformBufferPooling` was not promoted into an invented
compiled default. The RHI command-list and OpenGL UBO capacity candidates
therefore keep their existing rankings, but neither gains FPS credit from this
static audit. Evidence is in
[`artifacts/unreal-uniform-command-pipeline-audit-20260815.json`](../artifacts/unreal-uniform-command-pipeline-audit-20260815.json).

An isolated runtime query then resolved the static unknown without inventing a
compiled default. A profile containing only `r.UniformBufferPooling=1` logged
`1 -> 1`, so general Unreal uniform-buffer pooling is already effective. It is
a rejected no-op, not another candidate. The queued OpenGL UBO profile remains
the single capacity change `0 -> 16777216`; this makes the synthetic pooling
result more mechanically relevant while still requiring authenticated
late-PvP validation. The AVD was returned to zero devices/processes, no lock,
and pipe transport. See
[`artifacts/unreal-uniform-buffer-pooling-runtime-audit-20260815.json`](../artifacts/unreal-uniform-buffer-pooling-runtime-audit-20260815.json).

The animation-budget policy itself was decoded end to end rather than adding
more interacting knobs. Twenty-one exact compiled values cover time allocation,
interpolation, offscreen ticking, smoothing, reduction thresholds, throttles,
and significance. The direct budget is compiled at 1.0 ms, low view scalability
raises it to 1.5 ms, and saved settings later raise it again to 1.85 ms. The
queued profile changes only that value back to 1.0 ms and its lower-priority
override was already proven blocked at startup. Tightening max tick rate,
interpolation, offscreen, minimum-quality, or significance behavior would
confound the test and alter unit cadence/visibility semantics, so those controls
were not queued. This supports the existing priority-three ranking without
promoting it. The policy audit is
[`artifacts/unreal-animation-budget-policy-audit-20260815.json`](../artifacts/unreal-animation-budget-policy-audit-20260815.json).

## Historical and rejected findings

- Direct TFT Vulkan, external UE command lines, raw native GLES, more RAM, an
  eighth vCPU, Android Game Mode FPS caps, stretched windows, scrcpy video, and
  broad shader prewarm did not solve the verified problem.
- Pinning RHIThread to CPUs 0–1 worsened frame time and was rolled back.
- Restricting PSO workers to CPUs 2–6 produced a worse directional sample and
  was rolled back.
- A 30-minute sustained Trial was not completed; partial runs remain diagnostic.
- The 1800p result is provisional because power source and tail latency were not
  controlled identically.
- The old low-resolution, pre-fast-quality, menu, lobby, and login observations
  are historical and must not be combined with fixed-stage battle data.

Negative results remain represented by explicit profiles where reproducibility
has engineering value. Their status is indexed in
[Launch profiles](launch-profiles.md).

## September buffer-view cache

The September 8 current-game trace identified synchronous Vulkan buffer-view
creation in guest ANGLE as a substantial RHI cost. A bounded Android Vulkan
layer now shares identical active views with reference counts and retains
released views until eviction or buffer/device teardown. The pinned global
game automatically uses the built layer; other game revisions fall back until
validated. App-targeted layer settings and the staged library are journaled and
recovered on shutdown or the next cold launch, including a cache-disabled launch.

The final 65,536-entry layer improved an unchanged Trial planning scene from
41.34 to 59.48 FPS (+43.9%), with median p95 falling from 34.06 to 18.67 ms.
Two stage-1-8 fights with opposite switch orders improved by 59.0% and 72.4%.
The changing combat load and early Trial stage limit extrapolation to late PvP.
Native lifecycle/thread/dispatch tests, Android HWASan/UBSan, real GPU readbacks,
and interrupted-launch recovery passed. The separate KosmicKrisp host-driver
screen was negative for this guest-ANGLE workload. Full measurements and limits
are in [the experiment report](performance-experiments-20260908.md).

## TFT 18.6 match-entry crash

Global `18.6-5845453` reproduced a GameThread SIGSEGV at `libUnreal.so+0x3a575bc`
immediately after entering a match. The failing instruction dereferenced a
missing selector-property map entry at address `0x8`; the key was `SRC_GPUFamily`.
The startup `DeviceProfile=Android_Codex` override skipped normal Android device
detection, leaving that map uninitialized. Launcher shutdown after game exit
then closed Android as well.

Removing the override restored device detection and match entry, but the stock
profile also changed framebuffer scaling and graphics settings. The fix keeps
normal selection and remaps the selected Mactician graphics profile to
`Android_MatchedFragments`, inheriting from `Android` to avoid a parent cycle.
Every existing graphics CVar remains unchanged. Historical experiment profiles
stay intact; only the runtime copy is adapted. A deferred `dp.Override` through
`-ExecCmds` was ignored by this Shipping build and is not used.

On M1 Max, the corrected run logged `SRC_GPUFamily: Apple M1 Max`, selected the
adapted profile, restored the 3840x2160 framebuffer and normal UI scale, and
survived more than four minutes in the same live match with an empty Android
crash buffer. Unit tests cover command-line generation, preservation of all
graphics CVars, parent selection, and repeated profile preparation. Other
editions and hardware were not exercised in this validation.
