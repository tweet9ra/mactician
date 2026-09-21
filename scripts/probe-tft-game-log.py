#!/usr/bin/env python3
"""Read-only local smoke test using the same command/parser as the launcher.

Prints allowlisted observations and wall time only. Does not save raw game logs,
start Android, change logging or send telemetry. Run after launching TFT.
"""
import argparse
import base64
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--interval", type=float, default=15)
    parser.add_argument("--package", choices=["com.riotgames.league.teamfighttactics", "com.riotgames.league.teamfighttacticsvn"], default="com.riotgames.league.teamfighttactics")
    parser.add_argument("--bracket", action="store_true", help="Read both boundaries around a two-second wait; no frame collector or telemetry")
    args = parser.parse_args()
    if not 1 <= args.samples <= 120 or not 5 <= args.interval <= 60:
        parser.error("use 1–120 samples at 5–60 second intervals")
    root = Path(__file__).resolve().parent.parent
    binary = root / "launcher/.build/tft-game-log-probe"
    binary.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "swiftc", "-O", str(root / "launcher/Sources/GameLogDiagnostics.swift"),
                    str(root / "tools/tft-game-log-probe.swift"), "-o", str(binary)], check=True)
    command = subprocess.check_output([str(binary), "--command", args.package], text=True)
    adb = Path.home() / "Library/Application Support/Mactician/sdk/platform-tools/adb"
    for index in range(args.samples):
        if index:
            time.sleep(args.interval)
        started = time.monotonic()
        try:
            read = subprocess.run([str(adb), "-P", "5038", "-s", "emulator-5582", "shell", command],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
            data = read.stdout if read.returncode == 0 else b""
        except (subprocess.TimeoutExpired, OSError):
            data = b""
        read_ms = round((time.monotonic() - started) * 1000, 1)
        if args.bracket:
            before = data
            time.sleep(2)
            try:
                after = subprocess.run([str(adb), "-P", "5038", "-s", "emulator-5582", "shell", command], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
                data = after.stdout if after.returncode == 0 else b""
            except (subprocess.TimeoutExpired, OSError): data = b""
            pair = json.dumps([base64.b64encode(part).decode("ascii") for part in [before, data]]).encode()
            observation = json.loads(subprocess.check_output([str(binary), "--bracket"], input=pair))
            observation["bracket_ms"] = round((time.monotonic()-started)*1000, 1)
            print(json.dumps(observation, sort_keys=True), flush=True)
            continue
        decode_started = time.monotonic()
        if data:
            observation = json.loads(subprocess.check_output([str(binary), "--context"], input=data))
        else:
            observation = {"outcome": "read_failed"}
        observation["read_ms"] = read_ms
        observation["decode_ms"] = round((time.monotonic() - decode_started) * 1000, 1)
        print(json.dumps(observation, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
