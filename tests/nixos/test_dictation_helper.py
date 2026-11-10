#!/usr/bin/env python3
"""Model integrity, Voxtype configuration, delivery and history contracts for dictation."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
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
FAKE = {"name": "ggml-test.bin", "file": "ggml-test.bin", "url": "https://example.invalid/ggml-test.bin",
        "size": len(BODY), "sha256": hashlib.sha256(BODY).hexdigest()}
# A two-file stand-in for Parakeet's directory of files.
PARTS = {"encoder.onnx": bytes(range(256)) * 2048, "vocab.txt": b"token\n" * 1000}
FAKE_PARAKEET = {"dir": "parakeet-test", "files": [
    {"name": name, "url": f"https://example.invalid/{name}", "size": len(body),
     "sha256": hashlib.sha256(body).hexdigest()} for name, body in PARTS.items()]}
FAKE_MODELS = {"enhanced": {"dir": "", "files": [FAKE]}, "parakeet": FAKE_PARAKEET}


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
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_STATE_HOME": str(self.root / "state")})
        environment.start()
        self.addCleanup(environment.stop)
        for name, value in (("ENHANCED", FAKE), ("MODELS", FAKE_MODELS), ("PARAKEET_DIR", "parakeet-test")):
            patch = mock.patch.object(MODULE, name, value)
            patch.start()
            self.addCleanup(patch.stop)
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

        path = MODULE.download("enhanced", opener, progress.append)
        self.assertEqual(path, self.models / "ggml-test.bin")
        self.assertEqual(path.read_bytes(), BODY)
        self.assertEqual(starts, [(FAKE["url"], 0)])
        self.assertEqual(progress[-1], "progress 100")
        self.assertFalse(MODULE.partial_path().exists())
        self.assertTrue(MODULE.status()["installed"])

    def test_an_interrupted_download_resumes_from_its_partial_file(self) -> None:
        with self.assertRaises(MODULE.Failure) as failed:
            MODULE.download("enhanced", lambda url, start: Response(BODY, fail_after=300000), lambda line: None)
        self.assertEqual(failed.exception.code, "network")
        kept = MODULE.partial_path().stat().st_size
        self.assertGreater(kept, 0)
        self.assertFalse((self.models / "ggml-test.bin").exists(), "nothing half-written is loadable")

        starts = []

        def opener(url, start):
            starts.append(start)
            return Response(BODY[start:], status=206)

        MODULE.download("enhanced", opener, lambda line: None)
        self.assertEqual(starts, [kept])
        self.assertEqual((self.models / "ggml-test.bin").read_bytes(), BODY)

    def test_a_server_that_ignores_the_range_starts_over(self) -> None:
        self.models.mkdir(parents=True)
        MODULE.partial_path().write_bytes(b"stale bytes")
        MODULE.download("enhanced", lambda url, start: Response(BODY, status=200), lambda line: None)
        self.assertEqual((self.models / "ggml-test.bin").read_bytes(), BODY)

    def test_altered_bytes_are_discarded(self) -> None:
        altered = bytearray(BODY)
        altered[1000] ^= 0xFF
        with self.assertRaises(MODULE.Failure) as failed:
            MODULE.download("enhanced", lambda url, start: Response(bytes(altered)), lambda line: None)
        self.assertEqual(failed.exception.code, "checksum")
        self.assertFalse(MODULE.partial_path().exists())
        self.assertFalse((self.models / "ggml-test.bin").exists())

    def test_a_longer_body_than_the_model_is_refused(self) -> None:
        with self.assertRaises(MODULE.Failure) as failed:
            MODULE.download("enhanced", lambda url, start: Response(BODY + b"x"), lambda line: None)
        self.assertEqual(failed.exception.code, "checksum")
        self.assertFalse((self.models / "ggml-test.bin").exists())

    def test_too_little_free_space_downloads_nothing(self) -> None:
        opened = []
        usage = mock.Mock(free=len(BODY) - 1)
        with mock.patch.object(MODULE.shutil, "disk_usage", return_value=usage):
            with self.assertRaises(MODULE.Failure) as failed:
                MODULE.download("enhanced", lambda url, start: opened.append(start), lambda line: None)
        self.assertEqual(failed.exception.code, "space")
        self.assertEqual(opened, [])

    def test_remove_deletes_the_model_and_any_partial_file(self) -> None:
        self.models.mkdir(parents=True)
        (self.models / "ggml-test.bin").write_bytes(BODY)
        MODULE.partial_path().write_bytes(b"part")
        self.assertEqual(MODULE.remove(), {"removed": True, "installed": False, "model": "enhanced"})
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
            "m.download = lambda *a: (print('ready', flush=True), time.sleep(30))\n"
            "sys.exit(m.main(['download']))\n")
        process = subprocess.Popen(["python3", "-c", script], stdout=subprocess.PIPE, text=True,
                                   env=dict(os.environ))
        self.assertEqual(process.stdout.readline().strip(), "ready")
        self.assertTrue(partial.exists())
        process.terminate()
        self.assertEqual(process.wait(timeout=10), 143)
        process.stdout.close()
        self.assertFalse(partial.exists())



class ParakeetDownloadTests(HelperTest):
    def opener(self, starts=None):
        def open_part(url, start):
            if starts is not None:
                starts.append((url.rsplit("/", 1)[-1], start))
            return Response(PARTS[url.rsplit("/", 1)[-1]][start:], status=206 if start else 200)
        return open_part

    def test_every_file_is_verified_into_the_models_directory(self) -> None:
        progress = []
        directory = MODULE.download("parakeet", self.opener(), progress.append)
        self.assertEqual(directory, self.models / "parakeet-test")
        for name, body in PARTS.items():
            self.assertEqual((directory / name).read_bytes(), body)
        # One percentage over both files, ending at 100.
        values = [int(line.split()[1]) for line in progress]
        self.assertEqual(values, sorted(values))
        self.assertEqual(values[-1], 100)
        status = MODULE.status()["models"]
        self.assertTrue(status["parakeet"]["installed"])
        self.assertFalse(status["enhanced"]["installed"])

    def test_a_finished_file_is_kept_and_the_next_resumes(self) -> None:
        directory = self.models / "parakeet-test"
        directory.mkdir(parents=True)
        (directory / "encoder.onnx").write_bytes(PARTS["encoder.onnx"])
        (directory / ".vocab.txt.part").write_bytes(PARTS["vocab.txt"][:100])
        starts = []
        MODULE.download("parakeet", self.opener(starts), lambda line: None)
        self.assertEqual(starts, [("vocab.txt", 100)])
        self.assertTrue(MODULE.is_installed("parakeet"))

    def test_remove_takes_the_directory(self) -> None:
        MODULE.download("parakeet", self.opener(), lambda line: None)
        self.assertEqual(MODULE.remove("parakeet")["installed"], False)
        self.assertFalse((self.models / "parakeet-test").exists())

    def test_the_pinned_parakeet_files_are_the_reviewed_ones(self) -> None:
        source = PATH.read_text()
        self.assertIn('PARAKEET_REVISION = "8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce"', source)
        for name, size, digest in (
                ("encoder-model.int8.onnx", 652183999, "6139d2fa7e1b086097b277c7149725edbab89cc7c7ae64b23c741be4055aff09"),
                ("decoder_joint-model.int8.onnx", 18202004, "eea7483ee3d1a30375daedc8ed83e3960c91b098812127a0d99d1c8977667a70"),
                ("vocab.txt", 93939, "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d"),
                ("config.json", 97, "666903c76b9798caf2c210afd4f6cd60b08a8dbf9800ec8d7a3bc0d2148ac466")):
            self.assertIn(f'_parakeet("{name}", {size},\n                      "{digest}")', source)


class ParakeetApplyTests(HelperTest):
    def recorder(self):
        calls = []

        def runner(command):
            calls.append(command)
            if command[:2] == ["systemctl", "--user"]:
                return Done(stdout="active\n")
            return Done()
        return calls, runner

    def test_parakeet_is_given_its_section_before_the_engine_changes(self) -> None:
        MODULE.download("parakeet", lambda url, start: Response(PARTS[url.rsplit("/", 1)[-1]]), lambda line: None)
        calls, runner = self.recorder()
        result = MODULE.apply("parakeet", "en,nl", True, "", runner)
        self.assertEqual(result["model"], "parakeet")
        keys = [c[5] for c in calls if c[0] == "voxtype"]
        self.assertEqual(keys[:3], ["parakeet.model", "parakeet.streaming", "parakeet.on_demand_loading"])
        self.assertEqual(keys[-1], "engine")
        settings = {c[5]: c[6] for c in calls if c[0] == "voxtype"}
        self.assertEqual(settings["parakeet.model"], "parakeet-test")
        self.assertEqual(settings["engine"], "parakeet")
        self.assertEqual(settings["parakeet.on_demand_loading"], "false")

    def test_parakeet_is_only_named_once_it_is_installed(self) -> None:
        calls, runner = self.recorder()
        self.assertEqual(MODULE.apply("parakeet", "en", True, "", runner)["model"], "base")
        self.assertNotIn("parakeet.model", [c[5] for c in calls if c[0] == "voxtype"])

    def test_back_to_whisper_changes_the_engine_and_leaves_the_section(self) -> None:
        self.config.parent.mkdir(parents=True)
        self.config.write_text('engine = "parakeet"\n[parakeet]\nmodel = "parakeet-test"\nstreaming = true\n'
                               '[whisper]\nmodel = "base"\nlanguage = "en"\nstreaming = true\n'
                               'on_demand_loading = false\n[streaming]\nrevision_mode = true\n')
        calls, runner = self.recorder()
        MODULE.apply("base", "en", True, "", runner)
        self.assertEqual([c[4:] for c in calls if c[0] == "voxtype"], [["set", "engine", "whisper"]])


class CorrectionTests(unittest.TestCase):
    RULES = [{"heard": "cyber os", "write": "Cybex OS"}, {"heard": "whiz", "write": "Wiz"}]

    def test_whole_words_in_any_case_and_spacing(self) -> None:
        self.assertEqual(MODULE.correct("Install Cyber   OS and ask whiz.", self.RULES),
                         "Install Cybex OS and ask Wiz.")

    def test_parts_of_words_are_left_alone(self) -> None:
        self.assertEqual(MODULE.correct("cyberosis and whizzing", self.RULES), "cyberosis and whizzing")

    def test_broken_rules_are_skipped(self) -> None:
        self.assertEqual(MODULE.correct("a b", [{"heard": "", "write": "x"}, "nonsense", {"heard": "a"}]), "a b")

    def test_a_replacement_is_taken_literally(self) -> None:
        self.assertEqual(MODULE.correct("price", [{"heard": "price", "write": r"\1 $5"}]), r"\1 $5")


class TidyTests(unittest.TestCase):
    def test_hesitations_go_and_the_sentence_starts_with_a_capital(self) -> None:
        self.assertEqual(MODULE.basic_tidy("Um, so can you, uh, send it tomorrow, no wait, Friday?"),
                         "So can you send it tomorrow, no wait, Friday?")
        self.assertEqual(MODULE.basic_tidy("It works. Uhm, so we go. Hmm."), "It works. So we go.")

    def test_words_that_only_look_like_hesitations_stay(self) -> None:
        self.assertEqual(MODULE.basic_tidy("the umbrella said uh-huh to ermine"),
                         "The umbrella said uh-huh to ermine.")

    def test_english_i_is_a_capital_and_a_full_stop_closes_a_sentence(self) -> None:
        self.assertEqual(MODULE.basic_tidy("i think i'm ready"), "I think I'm ready.")
        self.assertEqual(MODULE.basic_tidy("ja ik ben er", ["nl"]), "Ja ik ben er.")
        self.assertEqual(MODULE.basic_tidy("ok then"), "Ok then", "two words are not a sentence")

    def test_dutch_hesitations(self) -> None:
        self.assertEqual(MODULE.basic_tidy("Eh, ik kom morgen, ehm, iets later.", ["en", "nl"]),
                         "Ik kom morgen iets later.")

    def test_only_hesitation_leaves_nothing(self) -> None:
        self.assertEqual(MODULE.basic_tidy("Um."), "")


class FakeProcess:
    """Popen for polish(): replies, fails or never finishes."""

    def __init__(self, reply: str = "", code: int = 0, hang: bool = False, output: Path | None = None) -> None:
        self.reply, self.code, self.hang, self.output = reply, code, hang, output
        self.commands = []
        self.written = io.StringIO()

    def __call__(self, command, **kwargs):
        self.commands.append((command, kwargs))
        self.stdin = self.written
        self.stdin.close = lambda: None
        self.stdout = io.StringIO(self.reply)
        self.stderr = io.StringIO("agent error")
        self.pid = 999999
        self.returncode = None
        if "-o" in command:
            Path(command[command.index("-o") + 1]).write_text(self.reply)
        return self

    def poll(self):
        if self.hang:
            return None
        self.returncode = self.code
        return self.code

    def wait(self):
        self.returncode = -15
        return -15


class PolishTests(unittest.TestCase):
    def setUp(self) -> None:
        patch = mock.patch.object(MODULE, "agent_path", lambda name: f"/usr/bin/{name}")
        patch.start()
        self.addCleanup(patch.stop)

    def test_claude_runs_once_without_tools_or_a_saved_session(self) -> None:
        process = FakeProcess("Can you send it on Friday?")
        self.assertEqual(MODULE.polish("So can you send it tomorrow, no wait, Friday?", "claude", popen=process),
                         "Can you send it on Friday?")
        command, kwargs = process.commands[0]
        self.assertEqual(command[:2], ["/usr/bin/claude", "-p"])
        for flag in ("--no-session-persistence", "--strict-mcp-config"):
            self.assertIn(flag, command)
        self.assertEqual(command[command.index("--tools") + 1], "")
        self.assertEqual(command[command.index("--model") + 1], "haiku")
        self.assertIn("Never add, explain", command[command.index("--system-prompt") + 1])
        self.assertIn("<dictation>\nSo can you", process.written.getvalue())
        self.assertTrue(kwargs["start_new_session"])

    def test_codex_runs_ephemeral_read_only_and_answers_in_a_file(self) -> None:
        process = FakeProcess("“Ship it on Tuesday.”")
        self.assertEqual(MODULE.polish("ship it monday i mean tuesday", "codex", popen=process), "Ship it on Tuesday.")
        command = process.commands[0][0]
        self.assertEqual(command[:2], ["/usr/bin/codex", "exec"])
        for flag in ("--ephemeral", "--skip-git-repo-check"):
            self.assertIn(flag, command)
        self.assertEqual(command[command.index("--sandbox") + 1], "read-only")
        self.assertTrue(process.written.getvalue().startswith(MODULE.POLISH_PROMPT))

    def test_a_reply_is_typed_as_one_line(self) -> None:
        self.assertEqual(MODULE.polish("first then second", "claude", popen=FakeProcess("First.\n\nThen second.\n")),
                         "First. Then second.")

    def test_an_answer_instead_of_a_rewrite_is_refused(self) -> None:
        with self.assertRaises(RuntimeError):
            MODULE.polish("What is Paris?", "claude", popen=FakeProcess("Paris is the capital of France. " * 20))
        with self.assertRaises(RuntimeError):
            MODULE.polish("words", "claude", popen=FakeProcess(""))

    def test_a_failed_or_slow_agent_is_an_error(self) -> None:
        with self.assertRaises(RuntimeError):
            MODULE.polish("words", "claude", popen=FakeProcess("x", code=1))
        with mock.patch.object(MODULE.os, "killpg") as killed:
            with self.assertRaises(RuntimeError) as failed:
                MODULE.polish("words", "claude", popen=FakeProcess(hang=True), timeout=0.1)
        self.assertIn("too long", str(failed.exception))
        killed.assert_called_once()

    def test_asking_for_the_original_stops_the_agent(self) -> None:
        with mock.patch.object(MODULE.os, "killpg"):
            with self.assertRaises(RuntimeError) as failed:
                MODULE.polish("words", "claude", abandoned=lambda: True, popen=FakeProcess(hang=True))
        self.assertEqual(str(failed.exception), "abandoned")

    def test_a_missing_agent_is_an_error(self) -> None:
        with mock.patch.object(MODULE, "agent_path", lambda name: None):
            with self.assertRaises(RuntimeError):
                MODULE.polish("words", "codex", popen=FakeProcess("x"))


class DeliverTests(HelperTest):
    def setUp(self) -> None:
        super().setUp()
        self.transcript = self.root / "session/transcript.txt"
        self.transcript.parent.mkdir()
        self.events = []
        self.typed = []
        self.window = {"class": "org.mozilla.thunderbird"}
        self.type_code = 0

    def runner(self, command):
        if command[0] == "hyprctl":
            return Done(stdout=json.dumps(self.window))
        if command[0] == "wtype":
            self.typed.append(command[-1])
            return Done(returncode=self.type_code)
        return Done()

    def deliver(self, text: str, polisher=None, **options):
        self.transcript.write_text(text)
        chosen = MODULE.options_of(json.dumps(options))
        return MODULE.deliver(self.transcript, chosen, self.events.append, self.runner,
                              polisher or (lambda *a, **k: self.fail("no polish")))

    def test_corrections_and_basic_tidy_are_typed_and_kept(self) -> None:
        code = self.deliver("um, ask whiz about cyber os", corrections=[{"heard": "whiz", "write": "Wiz"},
                                                                        {"heard": "cyber os", "write": "Cybex OS"}])
        self.assertEqual(code, 0)
        self.assertEqual(self.typed, ["Ask Wiz about Cybex OS."])
        self.assertEqual([event["event"] for event in self.events], ["tidying", "typing", "result"])
        result = self.events[-1]
        self.assertEqual((result["status"], result["original"], result["tidied"], result["app"]),
                         ("typed", "um, ask Wiz about Cybex OS", True, "Thunderbird"))
        entry = MODULE.load_entries()[0]
        self.assertEqual((entry["text"], entry["status"], entry["tidy"], entry["words"]),
                         ("Ask Wiz about Cybex OS.", "typed", "basic", 5))
        self.assertEqual(oct(MODULE.history_path().stat().st_mode & 0o777), "0o600")

    def test_terminals_get_the_words_as_heard(self) -> None:
        self.window = {"class": "com.mitchellh.ghostty"}
        self.deliver("um git status")
        self.assertEqual(self.typed, ["um git status"])
        self.assertEqual([event["event"] for event in self.events], ["typing", "result"])
        self.typed.clear()
        self.deliver("um git status", skipCode=False)
        self.assertEqual(self.typed, ["Git status"])

    def test_polish_and_its_fallback(self) -> None:
        self.deliver("so send it tomorrow no wait friday", tidy="polish",
                     polisher=lambda text, agent, abandoned: "Send it on Friday.")
        self.assertEqual(self.typed[-1], "Send it on Friday.")
        self.assertEqual(self.events[0], {"event": "tidying", "mode": "polish"})

        def broken(*_args, **_kwargs):
            raise RuntimeError("claude did not answer")
        self.deliver("um so send it", tidy="polish", polisher=broken)
        self.assertEqual(self.typed[-1], "So send it.")
        self.assertTrue(self.events[-1]["polishFailed"])

    def test_the_original_can_be_asked_for_while_polishing(self) -> None:
        def slow(text, agent, abandoned):
            Path(str(self.transcript) + ".original").touch()
            self.assertTrue(abandoned())
            raise RuntimeError("abandoned")
        self.deliver("um so send it", tidy="polish", polisher=slow)
        self.assertEqual(self.typed, ["um so send it"])
        self.assertFalse(self.events[-1]["tidied"])
        self.assertFalse(Path(str(self.transcript) + ".original").exists())

    def test_words_that_could_not_be_typed_are_kept_even_when_nothing_is_saved(self) -> None:
        self.type_code = 1
        with mock.patch.object(MODULE, "copy_text", return_value=False):
            self.assertEqual(self.deliver("hello there friend", history="session"), 1)
        entries = MODULE.load_entries()
        self.assertEqual([(e["status"], e["text"]) for e in entries], [("failed", "Hello there friend.")])
        self.type_code = 0
        self.deliver("another one here", history="session")
        self.assertEqual(len(MODULE.load_entries()), 1, "a typed dictation is not saved")

    def test_a_recording_is_kept_only_when_asked(self) -> None:
        recording = Path(str(self.transcript) + ".wav")
        recording.write_bytes(b"RIFF")
        self.deliver("one two three")
        self.assertFalse(recording.exists())
        self.assertFalse(MODULE.load_entries()[0]["audio"])
        recording.write_bytes(b"RIFF")
        self.deliver("four five six", keepAudio=True)
        entry = MODULE.load_entries()[0]
        self.assertTrue(entry["audio"])
        self.assertEqual(MODULE.recording_of(entry["id"]).read_bytes(), b"RIFF")
        self.assertFalse(recording.exists())

    def test_nothing_heard_types_and_keeps_nothing(self) -> None:
        self.assertEqual(self.deliver("  "), 3)
        self.assertEqual(self.typed, [])
        self.assertEqual(MODULE.load_entries(), [])

    def test_options_are_validated(self) -> None:
        options = MODULE.options_of('{"tidy": "rm -rf", "agent": "x", "history": 5, "languages": "en,;x", "corrections": 3}')
        self.assertEqual((options["tidy"], options["agent"], options["history"], options["languages"], options["corrections"]),
                         ("basic", "claude", "month", ["en"], []))
        self.assertEqual(MODULE.options_of("not json")["tidy"], "basic")


class HistoryTests(HelperTest):
    def entry(self, text: str, age: float, status: str = "typed") -> dict:
        return {"id": MODULE.uuid.uuid4().hex[:12], "time": time.time() - age, "text": text, "original": text,
                "words": len(text.split()), "status": status, "tidy": "off", "audio": False, "app": ""}

    def test_thirty_days_keeps_failed_dictations_until_typed(self) -> None:
        old, failed, fresh = self.entry("old", 40 * 86400), self.entry("lost", 40 * 86400, "failed"), self.entry("new", 60)
        MODULE.save_entries([fresh, failed, old])
        listed = MODULE.history_list("month")
        self.assertEqual([e["text"] for e in listed["entries"]], ["new", "lost"])
        self.assertEqual(listed["weekWords"], 1)
        self.assertEqual(len(MODULE.history_list("forever")["entries"]), 2, "the old one is gone for good")

    def test_the_same_fix_twice_becomes_a_suggestion_until_answered(self) -> None:
        first, second = self.entry("send it to voxtipe now", 10), self.entry("is voxtipe running", 5)
        MODULE.save_entries([second, first])
        args = mock.Mock(action="edit", value=[first["id"], "send it to Voxtype now"])
        with mock.patch.object(MODULE, "emit_json"):
            MODULE.history_command(args, "month")
        self.assertEqual(MODULE.suggestions(), [])
        args.value = [second["id"], "is Voxtype running"]
        with mock.patch.object(MODULE, "emit_json"):
            MODULE.history_command(args, "month")
        self.assertEqual(MODULE.suggestions(), [{"heard": "voxtipe", "write": "Voxtype", "count": 2}])
        stored = MODULE.find(MODULE.load_entries(), second["id"])
        self.assertEqual((stored["text"], stored["edited"]), ("is Voxtype running", True))
        MODULE.forget("voxtipe", "Voxtype")
        self.assertEqual(MODULE.suggestions(), [])

    def test_changed_words_are_short_replacements_and_case_fixes(self) -> None:
        self.assertEqual(MODULE.changed_words("ask whiz now", "ask Wiz now"), [("whiz", "Wiz")])
        self.assertEqual(MODULE.changed_words("cybex is fine", "Cybex is fine"), [("cybex", "Cybex")])
        self.assertEqual(MODULE.changed_words("one", "a completely different sentence of many words"), [])

    def test_delete_and_clear_take_the_recordings_too(self) -> None:
        kept, gone = self.entry("kept", 1), self.entry("gone", 2)
        MODULE.audio_dir().mkdir(parents=True)
        for entry in (kept, gone):
            MODULE.recording_of(entry["id"]).write_bytes(b"RIFF")
        MODULE.save_entries([kept, gone])
        with mock.patch.object(MODULE, "emit_json"):
            MODULE.history_command(mock.Mock(action="delete", value=[gone["id"]]), "month")
            self.assertFalse(MODULE.recording_of(gone["id"]).exists())
            self.assertEqual([e["id"] for e in MODULE.load_entries()], [kept["id"]])
            MODULE.history_command(mock.Mock(action="clear", value=[]), "month")
        self.assertEqual(MODULE.load_entries(), [])
        self.assertFalse(MODULE.recording_of(kept["id"]).exists())

    def test_typing_a_failed_dictation_again_marks_it_typed(self) -> None:
        failed = self.entry("words", 1, "failed")
        MODULE.save_entries([failed])
        with mock.patch.object(MODULE, "emit_json"), mock.patch.object(MODULE, "type_text", return_value=0), \
                mock.patch.object(MODULE.time, "sleep"):
            self.assertEqual(MODULE.history_command(mock.Mock(action="type", value=[failed["id"]]), "month"), 0)
        self.assertEqual(MODULE.load_entries()[0]["status"], "typed")

    def test_an_unknown_id_is_an_error(self) -> None:
        with mock.patch.object(MODULE, "emit_json") as said:
            self.assertEqual(MODULE.history_command(mock.Mock(action="delete", value=["nope"]), "month"), 1)
        said.assert_called_once_with({"error": "no such dictation"})


class WindowTests(unittest.TestCase):
    def test_terminals_and_editors_are_code(self) -> None:
        for name in ("com.mitchellh.ghostty", "kitty", "Alacritty", "code", "dev.zed.Zed", "jetbrains-idea"):
            self.assertTrue(MODULE.is_code(name), name)
        for name in ("google-chrome", "brave-browser", "org.mozilla.thunderbird", "Slack", ""):
            self.assertFalse(MODULE.is_code(name), name)

    def test_app_names(self) -> None:
        self.assertEqual(MODULE.app_name("com.mitchellh.ghostty"), "Ghostty")
        self.assertEqual(MODULE.app_name("org.gnome.Calculator"), "Calculator")
        # Google Chrome on Wayland and under XWayland, and Brave, still on offer.
        self.assertEqual(MODULE.app_name("google-chrome"), "Chrome")
        self.assertEqual(MODULE.app_name("Google-chrome"), "Chrome")
        self.assertEqual(MODULE.app_name("brave-browser"), "Brave")
        self.assertEqual(MODULE.app_name("brave-origin"), "Brave")
        self.assertEqual(MODULE.app_name(""), "")

    def test_the_session_or_the_first_instance_answers(self) -> None:
        calls = []

        def runner(command):
            calls.append(command)
            return Done(returncode=1) if len(calls) == 1 else Done(stdout='{"class": "kitty"}')
        self.assertEqual(MODULE.focused_window(runner), {"class": "kitty"})
        self.assertEqual(calls[1], ["hyprctl", "-i", "0", "-j", "activewindow"])

if __name__ == "__main__":
    unittest.main()
