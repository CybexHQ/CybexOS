#!/usr/bin/env python3
"""Model integrity, Voxtype configuration and typing contracts for dictation."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import urllib.error


ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "desktop/quickshell/scripts/dictation.py"
SPEC = importlib.util.spec_from_file_location("dictation_helper", PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

BODY = bytes(range(256)) * 4096          # 1 MiB stand-in for the model
FAKE = {"file": "ggml-test.bin", "url": "https://example.invalid/ggml-test.bin",
        "size": len(BODY), "sha256": hashlib.sha256(BODY).hexdigest()}


class Response:
    def __init__(self, body: bytes, status: int = 200, fail_after: int | None = None) -> None:
        self.stream = io.BytesIO(body)
        self.status = status
        self.fail_after = fail_after
        self.sent = 0

    def read(self, size: int) -> bytes:
        if self.fail_after is not None and self.sent >= self.fail_after:
            raise urllib.error.URLError("connection reset")
        block = self.stream.read(min(size, 65536))
        self.sent += len(block)
        return block

    def __enter__(self):
        return self

    def __exit__(self, *exc) -> None:
        self.stream.close()


class Done:
    def __init__(self, returncode: int = 0, stdout: str = "", stderr: str = "") -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


class HelperTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="cybexos-dictation-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        environment = mock.patch.dict(os.environ, {
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_CONFIG_HOME": str(self.root / "config")})
        environment.start()
        self.addCleanup(environment.stop)
        enhanced = mock.patch.object(MODULE, "ENHANCED", FAKE)
        enhanced.start()
        self.addCleanup(enhanced.stop)
        margin = mock.patch.object(MODULE, "SPACE_MARGIN", 0)
        margin.start()
        self.addCleanup(margin.stop)
        self.models = self.root / "data/voxtype/models"
        self.config = self.root / "config/voxtype/config.toml"


class DownloadTests(HelperTest):
    def test_a_verified_model_is_renamed_into_place(self) -> None:
        starts, progress = [], []

        def opener(url, start):
            starts.append((url, start))
            return Response(BODY)

        path = MODULE.download(opener, progress.append)
        self.assertEqual(path, self.models / "ggml-test.bin")
        self.assertEqual(path.read_bytes(), BODY)
        self.assertEqual(starts, [(FAKE["url"], 0)])
        self.assertEqual(progress[-1], "progress 100")
        self.assertFalse(MODULE.partial_path().exists())
        self.assertTrue(MODULE.status()["installed"])

    def test_an_interrupted_download_resumes_from_its_partial_file(self) -> None:
        with self.assertRaises(MODULE.Failure) as failed:
            MODULE.download(lambda url, start: Response(BODY, fail_after=300000), lambda line: None)
        self.assertEqual(failed.exception.code, "network")
        kept = MODULE.partial_path().stat().st_size
        self.assertGreater(kept, 0)
        self.assertFalse((self.models / "ggml-test.bin").exists(), "nothing half-written is loadable")

        starts = []

        def opener(url, start):
            starts.append(start)
            return Response(BODY[start:], status=206)

        MODULE.download(opener, lambda line: None)
        self.assertEqual(starts, [kept])
        self.assertEqual((self.models / "ggml-test.bin").read_bytes(), BODY)

    def test_a_server_that_ignores_the_range_starts_over(self) -> None:
        self.models.mkdir(parents=True)
        MODULE.partial_path().write_bytes(b"stale bytes")
        MODULE.download(lambda url, start: Response(BODY, status=200), lambda line: None)
        self.assertEqual((self.models / "ggml-test.bin").read_bytes(), BODY)

    def test_altered_bytes_are_discarded(self) -> None:
        altered = bytearray(BODY)
        altered[1000] ^= 0xFF
        with self.assertRaises(MODULE.Failure) as failed:
            MODULE.download(lambda url, start: Response(bytes(altered)), lambda line: None)
        self.assertEqual(failed.exception.code, "checksum")
        self.assertFalse(MODULE.partial_path().exists())
        self.assertFalse((self.models / "ggml-test.bin").exists())

    def test_a_longer_body_than_the_model_is_refused(self) -> None:
        with self.assertRaises(MODULE.Failure) as failed:
            MODULE.download(lambda url, start: Response(BODY + b"x"), lambda line: None)
        self.assertEqual(failed.exception.code, "checksum")
        self.assertFalse((self.models / "ggml-test.bin").exists())

    def test_too_little_free_space_downloads_nothing(self) -> None:
        opened = []
        usage = mock.Mock(free=len(BODY) - 1)
        with mock.patch.object(MODULE.shutil, "disk_usage", return_value=usage):
            with self.assertRaises(MODULE.Failure) as failed:
                MODULE.download(lambda url, start: opened.append(start), lambda line: None)
        self.assertEqual(failed.exception.code, "space")
        self.assertEqual(opened, [])

    def test_remove_deletes_the_model_and_any_partial_file(self) -> None:
        self.models.mkdir(parents=True)
        (self.models / "ggml-test.bin").write_bytes(BODY)
        MODULE.partial_path().write_bytes(b"part")
        self.assertEqual(MODULE.remove(), {"removed": True, "installed": False})
        self.assertEqual(list(self.models.iterdir()), [])

    def test_the_pinned_model_is_the_reviewed_one(self) -> None:
        source = PATH.read_text()
        self.assertIn("5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin", source)
        self.assertIn('"size": 874188075', source)
        self.assertIn("317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1", source)


class ApplyTests(HelperTest):
    def write_config(self, text: str) -> None:
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_text(text)

    def recorder(self, active: str = "active"):
        calls = []

        def runner(command):
            calls.append(command)
            if command[:2] == ["systemctl", "--user"] and "show" in command:
                return Done(stdout=active + "\n")
            return Done()
        return calls, runner

    def test_only_keys_that_differ_are_set_and_the_daemon_restarts(self) -> None:
        self.write_config('[whisper]\nmodel = "base"\nlanguage = "en"\nstreaming = true\n'
                          'on_demand_loading = false\n[streaming]\nrevision_mode = true\n')
        calls, runner = self.recorder()
        result = MODULE.apply("base", "en,nl", True, "", runner)
        self.assertEqual(result, {"changed": ["whisper.language"], "restarted": True, "model": "base"})
        self.assertEqual(calls[0], ["voxtype", "--config", str(self.config), "config", "set",
                                    "whisper.language", "en,nl"])
        self.assertEqual(calls[-1], ["systemctl", "--user", "restart", "voxtype.service"])

    def test_an_unchanged_configuration_touches_nothing(self) -> None:
        self.write_config('[whisper]\nmodel = "base"\nlanguage = ["en", "nl"]\nstreaming = false\n'
                          'on_demand_loading = true\n[streaming]\nrevision_mode = false\n')
        calls, runner = self.recorder()
        self.assertEqual(MODULE.apply("base", "en,nl", False, "", runner),
                         {"changed": [], "restarted": False, "model": "base"})
        self.assertEqual(calls, [])

    def test_the_enhanced_model_is_only_named_once_it_is_installed(self) -> None:
        self.write_config('[whisper]\nmodel = "base"\n')
        calls, runner = self.recorder()
        self.assertEqual(MODULE.apply("enhanced", "en", True, "", runner)["model"], "base")
        self.assertNotIn("whisper.model", [c[5] for c in calls if c[0] == "voxtype"])

        self.models.mkdir(parents=True)
        (self.models / "ggml-test.bin").write_bytes(BODY)
        calls, runner = self.recorder()
        self.assertEqual(MODULE.apply("enhanced", "en", True, "", runner)["model"], "enhanced")
        self.assertIn(["voxtype", "--config", str(self.config), "config", "set",
                       "whisper.model", "ggml-test.bin"], calls)

    def test_live_text_keeps_the_model_loaded_and_turning_it_off_frees_it(self) -> None:
        self.write_config('[whisper]\nmodel = "base"\nlanguage = "en"\n')
        calls, runner = self.recorder()
        MODULE.apply("base", "en", False, "", runner)
        settings = {c[5]: c[6] for c in calls if c[0] == "voxtype"}
        self.assertEqual(settings, {"whisper.streaming": "false", "whisper.on_demand_loading": "true",
                                    "streaming.revision_mode": "false"})

    def test_vocabulary_becomes_one_line_of_context_and_clearing_it_unsets_it(self) -> None:
        self.write_config('[whisper]\nmodel = "base"\nlanguage = "en"\nstreaming = true\n'
                          'on_demand_loading = false\n[streaming]\nrevision_mode = true\n')
        calls, runner = self.recorder()
        MODULE.apply("base", "en", True, "Cybex,\n Hyprland\t Wiz", runner)
        self.assertEqual(calls[0][4:], ["set", "whisper.initial_prompt", "Cybex, Hyprland Wiz"])

        self.write_config('[whisper]\nmodel = "base"\nlanguage = "en"\nstreaming = true\n'
                          'on_demand_loading = false\ninitial_prompt = "Cybex"\n[streaming]\nrevision_mode = true\n')
        calls, runner = self.recorder()
        MODULE.apply("base", "en", True, "", runner)
        self.assertEqual(calls[0][4:], ["unset", "whisper.initial_prompt"])

    def test_a_stopped_daemon_is_not_started(self) -> None:
        calls, runner = self.recorder(active="inactive")
        self.assertFalse(MODULE.apply("base", "en", True, "", runner)["restarted"])
        self.assertNotIn(["systemctl", "--user", "restart", "voxtype.service"], calls)

    def test_a_failed_daemon_is_restarted_with_the_new_settings(self) -> None:
        calls, runner = self.recorder(active="failed")
        self.assertTrue(MODULE.apply("base", "en", True, "", runner)["restarted"])

    def test_language_lists_and_vocabulary_are_validated(self) -> None:
        for languages in ("", "en,nl,de", "EN", "en;rm -rf", "auto"):
            with self.assertRaises(ValueError, msg=languages):
                MODULE.desired("base", languages, True, "")
        with self.assertRaises(ValueError):
            MODULE.desired("base", "en", True, "x" * 401)

    def test_a_refused_key_is_reported(self) -> None:
        def runner(command):
            return Done(returncode=2, stderr="error: invalid value")
        with self.assertRaises(RuntimeError) as failed:
            MODULE.apply("base", "en", True, "", runner)
        self.assertIn("invalid value", str(failed.exception))


class CpuTests(HelperTest):
    def cpuinfo(self, flags: str) -> Path:
        path = self.root / "cpuinfo"
        path.write_text(f"processor\t: 0\nvendor_id\t: GenuineIntel\nflags\t\t: {flags}\n\n")
        return path

    def test_an_avx2_processor_runs_dictation(self) -> None:
        self.assertTrue(MODULE.cpu_supported(self.cpuinfo("fpu sse4_2 avx avx2 fma f16c bmi1 bmi2 avx512f")))

    def test_an_older_processor_does_not(self) -> None:
        # Sandy Bridge: AVX but no AVX2, FMA or BMI2.
        self.assertFalse(MODULE.cpu_supported(self.cpuinfo("fpu sse4_2 avx popcnt")))
        # Piledriver: FMA and F16C without AVX2.
        self.assertFalse(MODULE.cpu_supported(self.cpuinfo("fpu sse4_2 avx fma f16c bmi1")))

    def test_unknown_formats_are_not_refused(self) -> None:
        arm = self.root / "arm"
        arm.write_text("processor\t: 0\nFeatures\t: fp asimd\n")
        self.assertTrue(MODULE.cpu_supported(arm))
        self.assertTrue(MODULE.cpu_supported(self.root / "missing"))

    def test_status_reports_it(self) -> None:
        self.assertIn("cpu", MODULE.status())


class TypeTests(HelperTest):
    def test_words_are_typed_with_wtype(self) -> None:
        calls = []
        self.assertEqual(MODULE.type_text("Hallo wereld", lambda c: calls.append(c) or Done()), 0)
        self.assertEqual(calls, [["wtype", "-d", "1", "--", "Hallo wereld"]])

    def test_without_a_virtual_keyboard_the_words_go_to_the_clipboard(self) -> None:
        calls = []

        def runner(command):
            calls.append(command)
            return Done(returncode=1 if command[0] == "wtype" else 0)

        with mock.patch.object(MODULE.subprocess, "run", return_value=Done()) as copy:
            self.assertEqual(MODULE.type_text("-n not an option", runner), 2)
        self.assertEqual(copy.call_args.args[0], ["wl-copy"])
        self.assertEqual(copy.call_args.kwargs["input"], "-n not an option")
        self.assertEqual(calls[-1][0], "notify-send")

    def test_nothing_to_type_is_its_own_outcome(self) -> None:
        self.assertEqual(MODULE.type_text("", lambda c: self.fail("nothing runs")), 3)

    def test_the_command_line_reads_and_trims_the_transcript(self) -> None:
        transcript = self.root / "transcript.txt"
        transcript.write_text("  Words.\n")
        with mock.patch.object(MODULE, "type_text", return_value=0) as typed:
            self.assertEqual(MODULE.main(["type", str(transcript)]), 0)
        typed.assert_called_once_with("Words.")


class CancelTests(HelperTest):
    def test_cancelling_a_download_removes_its_partial_file(self) -> None:
        # The real script, stopped the way the shell stops it (SIGTERM).
        self.models.mkdir(parents=True)
        partial = self.models / ".ggml-large-v3-turbo-q8_0.bin.part"
        script = (
            "import importlib.util, signal, os, sys, time\n"
            f"spec = importlib.util.spec_from_file_location('d', {str(PATH)!r})\n"
            "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
            "m.partial_path().write_bytes(b'part')\n"
            "sys.argv = ['dictation.py', 'download']\n"
            "m.download = lambda: (print('ready', flush=True), time.sleep(30))\n"
            "sys.exit(m.main(['download']))\n")
        process = subprocess.Popen(["python3", "-c", script], stdout=subprocess.PIPE, text=True,
                                   env=dict(os.environ))
        self.assertEqual(process.stdout.readline().strip(), "ready")
        self.assertTrue(partial.exists())
        process.terminate()
        self.assertEqual(process.wait(timeout=10), 143)
        process.stdout.close()
        self.assertFalse(partial.exists())


if __name__ == "__main__":
    unittest.main()
