#!/usr/bin/env python3
"""Dictation's model, Voxtype configuration and typing (docs/dictation.md).

usage:
  dictation.py status
      One JSON object: whether the enhanced model is installed, its size, how
      much of an interrupted download is already on disk, and whether this
      processor can run dictation ("cpu", AVX2 and the rest).
  dictation.py download
      Fetches the enhanced model. Prints "progress N" (whole percent) while it
      arrives, then exactly one of "done" or "failed CODE"; the reason for a
      failure goes to stderr. Codes: network, space, checksum, write.
  dictation.py remove
      Deletes the enhanced model and any partial download. One JSON object.
  dictation.py apply --model base|enhanced --languages en[,nl] --live 1|0
                     [--vocabulary TEXT]
      Brings the keys Settings owns in Voxtype's config.toml in line, through
      `voxtype config set` (which keeps comments and other settings), and
      restarts the daemon when one changed. One JSON object.
  dictation.py type FILE
      Types a finished transcript into the focused window with wtype. Exit 0
      typed, 2 copied to the clipboard instead, 3 nothing to type, 1 failed.

The enhanced model comes from a pinned Hugging Face revision and is renamed
into place only once its length and SHA-256 match, so Voxtype never loads a
partial or altered file. A download stopped by SIGTERM (Cancel) removes its
partial file; one stopped by a network failure keeps it and resumes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tomllib
from typing import Callable
import urllib.error
import urllib.request


# Whisper large-v3-turbo, 8-bit (whisper.cpp ggml), from the same repository
# revision as the built-in base model (nix/modules/desktop.nix).
ENHANCED = {
    "file": "ggml-large-v3-turbo-q8_0.bin",
    "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/"
           "5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin",
    "size": 874188075,
    "sha256": "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1",
}
BASE_MODEL = "base"
# Room kept free beside the model so a download cannot fill the disk.
SPACE_MARGIN = 256 * 1024 * 1024
CHUNK = 1024 * 1024
TIMEOUT = 30
USER_AGENT = "CybexOS-dictation/1"
LANGUAGES = re.compile(r"^[a-z]{2,3}(?:,[a-z]{2,3})?$")
VOCABULARY_MAX = 400
SERVICE = "voxtype.service"


class Failure(Exception):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code


def emit(line: str) -> None:
    print(line, flush=True)


def data_home() -> Path:
    value = os.environ.get("XDG_DATA_HOME", "")
    return Path(value) if value.startswith("/") else Path.home() / ".local/share"


def config_home() -> Path:
    value = os.environ.get("XDG_CONFIG_HOME", "")
    return Path(value) if value.startswith("/") else Path.home() / ".config"


def models_dir() -> Path:
    return data_home() / "voxtype/models"


def config_path() -> Path:
    return config_home() / "voxtype/config.toml"


def model_path() -> Path:
    return models_dir() / ENHANCED["file"]


def partial_path() -> Path:
    return models_dir() / f".{ENHANCED['file']}.part"


def size_of(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def installed() -> bool:
    return size_of(model_path()) == ENHANCED["size"]


# What the voxtype unit's ConditionCPUFeature asks for, plus FMA, which
# systemd cannot name (nix/modules/desktop.nix).
CPU_FEATURES = ("sse4_2", "avx", "avx2", "fma", "f16c", "bmi2")


def cpu_supported(cpuinfo: Path = Path("/proc/cpuinfo")) -> bool:
    try:
        text = cpuinfo.read_text()
    except OSError:
        return True
    for line in text.splitlines():
        if line.startswith("flags"):
            flags = set(line.split(":", 1)[-1].split())
            return all(feature in flags for feature in CPU_FEATURES)
    # Not an x86 kernel's format: nothing to say against it.
    return True


def status() -> dict:
    return {"installed": installed(), "size": ENHANCED["size"],
            "partial": size_of(partial_path()), "file": ENHANCED["file"],
            "cpu": cpu_supported()}


# ---- download ----------------------------------------------------------------

def open_url(url: str, start: int):
    headers = {"User-Agent": USER_AGENT}
    if start:
        headers["Range"] = f"bytes={start}-"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=TIMEOUT)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def download(opener: Callable[[str, int], object] = open_url,
             progress: Callable[[str], None] = emit) -> Path:
    target = model_path()
    if installed():
        return target
    part = partial_path()
    total = ENHANCED["size"]
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise Failure("write", str(error)) from error
    start = size_of(part)
    if start >= total:
        start = 0
    free = shutil.disk_usage(target.parent).free
    if free < total - start + SPACE_MARGIN:
        raise Failure("space", f"{free} bytes free, {total - start} needed")
    try:
        response = opener(ENHANCED["url"], start)
    except (urllib.error.URLError, OSError, ValueError) as error:
        raise Failure("network", str(error)) from error
    with response:
        # A server that ignores the range sends the whole file again.
        if start and getattr(response, "status", 200) != 206:
            start = 0
        received = start
        shown = -1
        try:
            with part.open("ab" if start else "wb") as handle:
                while True:
                    try:
                        block = response.read(CHUNK)
                    except (urllib.error.URLError, OSError, ValueError) as error:
                        raise Failure("network", str(error)) from error
                    if not block:
                        break
                    received += len(block)
                    if received > total:
                        raise Failure("checksum", f"more than {total} bytes")
                    handle.write(block)
                    percent = received * 100 // total
                    if percent != shown:
                        shown = percent
                        progress(f"progress {percent}")
        except OSError as error:
            raise Failure("write", str(error)) from error
    if received != total:
        raise Failure("network", f"{received} of {total} bytes arrived")
    if sha256_of(part) != ENHANCED["sha256"]:
        part.unlink(missing_ok=True)
        raise Failure("checksum", "the model's SHA-256 does not match")
    try:
        os.chmod(part, 0o644)
        os.replace(part, target)
    except OSError as error:
        raise Failure("write", str(error)) from error
    return target


def remove() -> dict:
    removed = False
    for path in (model_path(), partial_path()):
        try:
            path.unlink()
            removed = True
        except FileNotFoundError:
            pass
    return {"removed": removed, "installed": installed()}


# ---- Voxtype configuration ---------------------------------------------------

def vocabulary_line(value: str) -> str:
    line = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]+", " ", value)).strip()
    if len(line) > VOCABULARY_MAX:
        raise ValueError("vocabulary is too long")
    return line


def desired(model: str, languages: str, live: bool, vocabulary: str) -> dict:
    """The value of every key Settings owns, None meaning "unset"."""
    if not LANGUAGES.match(languages):
        raise ValueError(f"not a language list: {languages}")
    use_enhanced = model == "enhanced" and installed()
    return {
        "whisper.model": ENHANCED["file"] if use_enhanced else BASE_MODEL,
        "whisper.language": languages,
        # Live words need the model resident: Voxtype streams only with a
        # preloaded model (docs/dictation.md).
        "whisper.streaming": live,
        "whisper.on_demand_loading": not live,
        # The shell's sessions write to a file, so revisions only edit text
        # in memory and the preview can follow Whisper's best guess.
        "streaming.revision_mode": live,
        "whisper.initial_prompt": vocabulary_line(vocabulary) or None,
    }


def current(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            config = tomllib.load(handle)
    except FileNotFoundError:
        config = {}
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise RuntimeError(f"cannot read {path}: {error}") from error
    values = {}
    for key in ("whisper.model", "whisper.language", "whisper.streaming",
                "whisper.on_demand_loading", "streaming.revision_mode", "whisper.initial_prompt"):
        section, name = key.split(".")
        value = config.get(section, {}).get(name)
        if isinstance(value, list):
            value = ",".join(str(item) for item in value)
        values[key] = value
    return values


def toml_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=30)


def restart_daemon(runner: Callable[[list[str]], subprocess.CompletedProcess] = run) -> bool:
    shown = runner(["systemctl", "--user", "show", SERVICE, "-p", "ActiveState", "--value"])
    if shown.returncode != 0 or shown.stdout.strip() not in ("active", "activating", "failed"):
        return False
    return runner(["systemctl", "--user", "restart", SERVICE]).returncode == 0


def apply(model: str, languages: str, live: bool, vocabulary: str,
          runner: Callable[[list[str]], subprocess.CompletedProcess] = run) -> dict:
    path = config_path()
    want = desired(model, languages, live, vocabulary)
    have = current(path)
    changed = []
    for key, value in want.items():
        if value is None:
            if have.get(key) in (None, ""):
                continue
            command = ["voxtype", "--config", str(path), "config", "unset", key]
        else:
            if have.get(key) == value:
                continue
            command = ["voxtype", "--config", str(path), "config", "set", key, toml_value(value)]
        result = runner(command)
        if result.returncode != 0:
            raise RuntimeError(f"{' '.join(command[3:6])}: {result.stderr.strip() or result.stdout.strip()}")
        changed.append(key)
    restarted = restart_daemon(runner) if changed else False
    return {"changed": changed, "restarted": restarted,
            "model": "enhanced" if want["whisper.model"] == ENHANCED["file"] else BASE_MODEL}


# ---- typing ------------------------------------------------------------------

def type_text(text: str, runner: Callable[[list[str]], subprocess.CompletedProcess] = run) -> int:
    if text == "":
        return 3
    try:
        if runner(["wtype", "-d", "1", "--", text]).returncode == 0:
            return 0
    except (OSError, subprocess.TimeoutExpired):
        pass
    # No virtual keyboard (or it failed): the words are not lost.
    try:
        copied = subprocess.run(["wl-copy"], input=text, text=True, timeout=10).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        copied = False
    if not copied:
        return 1
    try:
        runner(["notify-send", "--app-name=Dictation", "Dictation copied",
                "Your words could not be typed here. Paste them with Ctrl+V."])
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 2


# ---- command line --------------------------------------------------------------

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="dictation.py")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("download")
    commands.add_parser("remove")
    applying = commands.add_parser("apply")
    applying.add_argument("--model", choices=("base", "enhanced"), required=True)
    applying.add_argument("--languages", required=True)
    applying.add_argument("--live", choices=("0", "1"), required=True)
    applying.add_argument("--vocabulary", default="")
    typing = commands.add_parser("type")
    typing.add_argument("file")
    args = parser.parse_args(argv)

    if args.command == "status":
        emit(json.dumps(status()))
        return 0
    if args.command == "remove":
        emit(json.dumps(remove()))
        return 0
    if args.command == "download":
        def cancelled(_signum, _frame):
            partial_path().unlink(missing_ok=True)
            os._exit(143)
        signal.signal(signal.SIGTERM, cancelled)
        try:
            download()
        except Failure as failure:
            print(failure, file=sys.stderr)
            emit(f"failed {failure.code}")
            return 1
        emit("done")
        return 0
    if args.command == "apply":
        try:
            result = apply(args.model, args.languages, args.live == "1", args.vocabulary)
        except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            emit(json.dumps({"error": str(error)}))
            return 1
        emit(json.dumps(result))
        return 0
    try:
        text = Path(args.file).read_text(encoding="utf-8").strip()
    except OSError as error:
        print(error, file=sys.stderr)
        return 1
    return type_text(text)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
