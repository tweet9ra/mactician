#!/usr/bin/env python3
"""Capture paired Vulkan-cache windows in one game process.

The parent benchmark supplies the scene, profile, variant, output directory and
expected cache SHA-256. Every accepted block requires a matching scene in its
boundary screenshots and attested mode in the game process. OCR, APK hashing
and graphics metadata run after the timed sequence. Host power/thermal checks
bracket the entire sequence, so a change invalidates every block. The previous
after-image serves as the next before-image and is explicitly recorded.

This produces early-Trial evidence; changing combat load still requires
opposite switch orders in independent fights. Do not pool rejected windows.
"""
import datetime, hashlib, json, os, pathlib, re, shlex, shutil, statistics, subprocess, sys, time
root = pathlib.Path(__file__).resolve().parents[1]
env = os.environ.copy()
adb = [str(pathlib.Path(env['TFT_ROOT_SDK']) / 'platform-tools/adb'), '-P', env.get('TFT_ADB_SERVER_PORT', '5038'), '-s', env.get('TFT_SERIAL', 'emulator-5584')]
package = 'com.riotgames.league.teamfighttactics'
activity = package + '/com.epicgames.unreal.GameActivity'
prop = 'debug.mactician.vk_view_cache'
run_root = pathlib.Path(env['TFT_MEASUREMENT_ROOT'])
receipt = run_root.parent / 'live-cache-blocks.json'
phase = env['TFT_EXPECTED_PHASE']
stage = env['TFT_EXPECTED_STAGE']
order = [int(v) for v in env.get('TFT_CACHE_BLOCK_ORDER', '0,1,1,0,1,0,0,1' if phase == 'planning' else '0,1,0,1,0,1').split(',')]
assert order and all((v in (0, 1) for v in order))
window = float(env.get('TFT_CACHE_BLOCK_SECONDS', '2'))
assert 0.5 <= window <= 2

def command(args):
    return subprocess.check_output(args, text=True, timeout=15).strip()

def shell(*args):
    return command(adb + ['shell', *args])

def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')

def host():
    power = command(['pmset', '-g', 'ps']).splitlines()[0]
    custom = command(['pmset', '-g', 'custom'])
    thermal = command(['pmset', '-g', 'therm'])
    return {'power_source': power, 'power_settings': custom, 'thermal_state': thermal}

def capture(path):
    with path.open('wb') as f:
        subprocess.run(adb + ['exec-out', 'screencap', '-p'], stdout=f, check=True, timeout=10)

def classify(path):
    result = json.loads(command([str(root / 'runtime/tft-screen-classifier'), str(path)]))
    save_json(path.with_suffix('.json'), result)
    return result

def valid_scene(value):
    return value.get('state') == 'battle' and value.get('stage') == stage and (value.get('phase') == phase)

def layer_name():
    lines = shell('dumpsys', 'SurfaceFlinger', '--list').splitlines()
    matches = [v for v in lines if 'SurfaceView[' + activity + '](BLAST)' in v]
    if len(matches) != 1:
        raise RuntimeError('Expected one TFT SurfaceView')
    return re.sub(r'^RequestedLayerState\{(.*) parentId=[^}]*\}$', r'\1', matches[0])

def mode_attested(mode):
    if shell('pidof', package) != pid:
        return False
    lines = command(adb + ['logcat', '-d', '-v', 'threadtime', '-s', 'MacticianVkView:I']).splitlines()
    relevant = [l for l in lines if re.search(r'\s' + re.escape(pid) + r'\s+\d+\s+I\s+MacticianVkView:', l) and re.search(r'\benabled=[01]\b', l)]
    return bool(relevant and re.search(r'\benabled=' + str(mode) + r'\b', relevant[-1]))

def pacing(raw):
    stamps = []
    for line in raw.splitlines()[1:]:
        columns = line.split()
        if len(columns) == 3:
            value = int(columns[1])
            if 0 < value < 9223372036854775807:
                stamps.append(value)
    deltas = [(b - a) / 1000000.0 for a, b in zip(stamps, stamps[1:]) if 0 < b - a < 1000000000]
    if len(deltas) < 10:
        raise RuntimeError('Not enough valid presented frames')
    ordered = sorted(deltas)
    mean = statistics.mean(deltas)
    result = {'samples': len(deltas), 'rounds': 1, 'window_seconds': window, 'fps': round(1000 / mean, 3), 'mean_ms': round(mean, 6), **{f'p{p}_ms': ordered[(len(ordered) - 1) * p // 100] for p in (50, 95, 99)}, 'max_ms': max(deltas), 'frames_over_ms': {str(t): sum((v > t for v in deltas)) for t in (16.67, 20, 33.33, 40, 50, 60, 100)}}
    return (result, deltas)
original = shell('getprop', prop)
pid = shell('pidof', package)
assert pid.isdecimal()
layer = layer_name()
blocks = []
summaries = []
metadata_verified = False
previous_after = None

def save():
    save_json(receipt, {'schema_version': 2, 'metadata_verified': metadata_verified, 'capture_protocol': 'short_windows_sequence_host_gates_deferred_semantics_v4', 'phase': phase, 'stage': stage, 'same_game_pid': int(pid), 'order': order, 'blocks': blocks})
sequence_host_before = host()
try:
    for index, mode in enumerate(order, 1):
        shell('setprop', prop, str(mode))
        time.sleep(0.8 if phase == 'combat' else 2)
        utc = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        variant = env['TFT_VARIANT'] + f'_cache_{mode}_fast_block_{index}'
        directory = run_root / (utc + '__' + env['TFT_SCENE'] + '__' + variant)
        directory.mkdir(parents=True)
        block = {'index': index, 'mode': mode, 'accepted': False, 'summary_path': str(directory / 'summary.json')}
        if previous_after is None:
            before = capture(directory / 'before.png')
            before_source = 'fresh_capture'
        else:
            previous_path, before = previous_after
            shutil.copy2(previous_path, directory / 'before.png')
            before_source = 'previous_block_after'
        block['before_image_source'] = before_source
        if not mode_attested(mode):
            block['reason'] = 'pre_scene_or_mode_gate'
            blocks.append(block)
            save()
            break
        start = time.time()
        shell('dumpsys SurfaceFlinger --latency-clear ' + shlex.quote(layer))
        time.sleep(window)
        raw = shell('dumpsys SurfaceFlinger --latency ' + shlex.quote(layer))
        end = time.time()
        (directory / 'latency-round-1.txt').write_text(raw + '\n')
        after = capture(directory / 'after.png')
        previous_after = (directory / 'after.png', after)
        measured, deltas = pacing(raw)
        accepted = mode_attested(mode)
        block.update(accepted=False, measurement_checks_valid=accepted, reason='semantic_validation_pending', pacing=measured, start_epoch=start, end_epoch=end)
        (directory / 'frame-times.csv').write_text('round,frame,delta_ms\n' + ''.join((f'1,{i},{v:.6f}\n' for i, v in enumerate(deltas, 1))))
        summary = {'schema_version': 1, 'utc': utc, 'scene': env['TFT_SCENE'], 'variant': variant, 'semantic_gate': {'expected_stage': stage, 'expected_phase': phase, 'valid': None}, 'host': {'stable': None, 'sampling_scope': 'entire_block_sequence'}, 'pacing': measured, 'measurement_interval': {'start_epoch': start, 'end_epoch': end}, 'rollback': {'verified': None, 'reason': 'pending_outer_launcher_cleanup'}, 'live_cache': {'enabled': bool(mode), 'mode_attested_before_and_after': accepted, 'same_game_pid': int(pid), 'block_index': index}}
        save_json(directory / 'summary.json', summary)
        summaries.append((directory, summary))
        (directory / 'summary.txt').write_text(f"Paired cache block {index}: enabled={mode}, accepted=pending, FPS={measured['fps']}, p95={measured['p95_ms']}ms\n")
        blocks.append(block)
        save()
        print(f'Collected paired block {index}; semantic validation pending.', flush=True)
        if not accepted:
            break
    sequence_host_after = host()
    stable = sequence_host_before == sequence_host_after and 'AC Power' in sequence_host_before['power_source'] and ('No thermal warning' in sequence_host_before['thermal_state']) and (layer_name() == layer)
    if shell('pidof', package) != pid:
        raise RuntimeError('TFT process changed before metadata verification')
    maps = shell('cat', '/proc/' + pid + '/maps')
    paths = shell('pm', 'path', package).splitlines()
    base = [v[8:] for v in paths if v.endswith('/base.apk')]
    assert len(base) == 1
    actual_hash = shell('sha256sum', base[0]).split()[0]
    assert actual_hash == env['TFT_ANGLE_OPENGL_APK_SHA256']
    cache_paths = set(re.findall(r'/[^\s]*libVkLayer_Mactician[^\s]*\.so', maps))
    assert len(cache_paths) == 1
    cache_path = cache_paths.pop()
    cache_hash = shell('sha256sum', cache_path).split()[0]
    assert cache_hash == env['TFT_VULKAN_CACHE_EXPECTED_SHA256']
    profile = pathlib.Path(env['TFT_PROFILE_PATH'])
    gfx = {'renderer': 'angle-opengl', 'renderer_source': 'verified_active_overlay_sha256', 'guest_gl_driver': 'angle' if 'libGLESv2_angle.so' in maps else 'unknown', 'active_apk_sha256': actual_hash, 'profile_path': str(profile), 'profile_sha256': hashlib.sha256(profile.read_bytes()).hexdigest(), 'guest_vulkan_ranchu_mapped': 'vulkan.ranchu.so' in maps, 'cache_library_sha256': cache_hash, 'metadata_sampled': 'after_block_sequence'}
    device = {'serial': env['TFT_SERIAL'], 'display': shell('wm', 'size'), 'density': shell('wm', 'density')}
    metadata_verified = True
    for (directory, summary), block in zip(summaries, blocks):
        try:
            before = classify(directory / 'before.png')
            after = classify(directory / 'after.png')
            semantic = valid_scene(before) and valid_scene(after)
            summary['semantic_gate'].update(stage_before=before.get('stage'), stage_after=after.get('stage'), phase_before=before.get('phase'), phase_after=after.get('phase'), valid=semantic)
        except Exception as error:
            semantic = False
            summary['semantic_gate'].update(valid=False, error=type(error).__name__)
        block['accepted'] = block['measurement_checks_valid'] and semantic and stable
        summary['host'].update(stable=stable, before=sequence_host_before, after=sequence_host_after)
        block['reason'] = 'accepted' if block['accepted'] else 'semantic_or_measurement_gate_failed'
        summary.update(graphics=gfx, device=device)
        save_json(directory / 'summary.json', summary)
        (directory / 'summary.txt').write_text(f"Paired cache block {block['index']}: enabled={block['mode']}, accepted={block['accepted']}, FPS={summary['pacing']['fps']}, p95={summary['pacing']['p95_ms']}ms\n")
        print((directory / 'summary.txt').read_text().strip(), flush=True)
    save()
finally:
    shell('setprop ' + shlex.quote(prop) + ' ' + shlex.quote(original))
    save()
accepted = [b for b in blocks if b['accepted']]
if not metadata_verified or {b['mode'] for b in accepted} != {0, 1}:
    sys.exit(3)
selected = run_root / 'ZZ-live-selected'
selected.mkdir(exist_ok=True)
last = pathlib.Path(accepted[-1]['summary_path'])
shutil.copy2(last, selected / 'summary.json')
shutil.copy2(last.with_suffix('.txt'), selected / 'summary.txt')
