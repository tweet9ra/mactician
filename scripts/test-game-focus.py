#!/usr/bin/env python3
"""Exercise the guest resource fix without an Android device."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.riotgames.league.teamfighttactics"


class GameFocusTests(unittest.TestCase):
    def run_fix(self, suffix="", **settings):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pidof").write_text('#!/bin/sh\nexit "${GAME_RUNNING:-1}"\n')
            (root / "cmd").write_text('''#!/bin/sh
echo "$*" >> "$FOCUS_TEST_DIR/calls"
case "$2" in
    lookup)
        if [ -f "$FOCUS_TEST_DIR/enabled" ]; then
            [ "${VERIFY_FAIL:-0}" = 0 ] || exit 1
            echo "${VERIFIED_COLOR:-#0}"
        else
            echo "${INITIAL_COLOR:-#33ffffff}"
        fi ;;
    enable) touch "$FOCUS_TEST_DIR/enabled" ;;
    disable) rm -f "$FOCUS_TEST_DIR/enabled" ;;
esac
''')
            for name in ("pidof", "cmd"):
                (root / name).chmod(0o755)
            result = subprocess.run(
                ["sh", str(ROOT / "scripts/guest-game-focus.sh"), PACKAGE + suffix],
                env={**os.environ, "PATH": directory + ":" + os.environ["PATH"],
                     "FOCUS_TEST_DIR": directory, **settings},
                capture_output=True, text=True,
            )
            log = root / "calls"
            return result, log.read_text() if log.exists() else "", (root / "enabled").exists()

    def test_all_editions_use_their_own_resource(self):
        for suffix in ("", "vn", "tw"):
            with self.subTest(edition=suffix):
                result, calls, enabled = self.run_fix(suffix)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(enabled)
                self.assertIn(f"--target {PACKAGE + suffix}", calls)
                self.assertIn(f"{PACKAGE + suffix}:color/ripple_material_dark", calls)

    def test_running_game_is_never_reconfigured(self):
        result, calls, _ = self.run_fix(GAME_RUNNING="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_unknown_package_and_color_are_not_changed(self):
        for suffix, settings in (("invalid", {}), ("", {"INITIAL_COLOR": "#12345678"})):
            with self.subTest(suffix=suffix, settings=settings):
                result, calls, enabled = self.run_fix(suffix, **settings)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("fabricate", calls)
                self.assertFalse(enabled)

    def test_existing_transparent_resource_can_be_refreshed(self):
        result, _, enabled = self.run_fix(INITIAL_COLOR="#0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(enabled)

    def test_failed_verification_disables_the_overlay(self):
        for settings in ({"VERIFIED_COLOR": "#33ffffff"}, {"VERIFY_FAIL": "1"}):
            with self.subTest(settings=settings):
                result, calls, enabled = self.run_fix(**settings)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("overlay disable", calls)
                self.assertFalse(enabled)


if __name__ == "__main__":
    unittest.main()
