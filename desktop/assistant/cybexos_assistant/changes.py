"""Everything Wiz changed, so any of it can be undone later (docs/assistant.md).

A turn's file snapshots (policy.Snapshots) become entries when it finishes:

- one entry per preference in shell.json whose value changed ("setting"),
- one entry per widget created or changed under the plugins folder ("plugin"),
- one entry per other file created, changed or removed ("file").

The service adds entries for what its desktop tools did that no file shows:
an app installed or removed for this account ("app"), a routine created or
removed ("routine"), and a system change staged for review ("system", which
Software Update owns and undoes).

An entry can be undone while what it changed still holds its value: a
preference still has the value Wiz gave it, a file still has the content Wiz
left. A later entry that touched the same thing blocks it ("undo that
first"); a change made since by anyone else leaves it as it is ("changed
since"). Pre-images of files are kept on disk beside the log (0700, files
0600), so Undo survives a restart of the service.

The log follows `assistantHistory`: 30 days, forever, or nothing saved.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import tempfile

from . import policy
from .history import MONTH_MS, retention
from .protocol import LOG, encode, now_ms


MAX_ENTRIES = 1000
MAX_BLOB = policy.MAX_SNAPSHOT
SETTINGS_FILE = ".config/cybexos/shell.json"
PLUGINS = ".local/share/cybexos/plugins"
# Where the character stands, how his box is shown, and the file's schema
# number: runtime state, not something a person would undo.
RUNTIME_KEYS = frozenset({"v", "assistantShown", "assistantScreen", "assistantX", "assistantY", "assistantTuck",
                          "assistantExpanded", "assistantExpandedWidth"})
ENTRY = re.compile(r"^ch-[0-9a-f]{16}$")
KINDS = ("setting", "file", "plugin", "app", "routine", "system")
MISSING = object()


def digest(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


def state_digest(state):
    """sha256 of a file state from policy.file_state, None when absent."""
    return digest(policy.content(state))


def read_settings_file(path):
    """The parsed shell.json, {} when absent, None when it is not JSON."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    except (OSError, UnicodeDecodeError):
        return None
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def parse_settings(state):
    if state is None:
        return {}
    try:
        value = json.loads(state[0].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def setting_diff(before, after):
    """[(key, had_before, before, has_after, after)] for every key that changed."""
    found = []
    for key in sorted(set(before) | set(after)):
        if key in RUNTIME_KEYS:
            continue
        old, new = before.get(key, MISSING), after.get(key, MISSING)
        if old is MISSING and new is MISSING:
            continue
        if old is not MISSING and new is not MISSING and old == new:
            continue
        found.append((key, old is not MISSING, None if old is MISSING else old,
                      new is not MISSING, None if new is MISSING else new))
    return found


def plugin_of(path, home):
    """The plugin folder's name a path is inside of, or ""."""
    root = os.path.join(str(home), PLUGINS)
    if not policy.under(path, root) or path == root:
        return ""
    return os.path.relpath(path, root).split(os.sep)[0]


class ChangeLog:
    def __init__(self, directory, read_settings, home, settings_path=None):
        self.directory = Path(directory)
        self.read_settings = read_settings
        self.home = str(home)
        self.settings_path = Path(settings_path or os.path.join(self.home, SETTINGS_FILE))
        self.entries = []
        self.blobs = {}
        self.mode = "month"

    # ---- storage -----------------------------------------------------------

    @property
    def index(self):
        return self.directory / "changes.json"

    def _blob_path(self, name):
        return self.directory / "blobs" / name

    def load(self):
        self.mode = retention(self.read_settings())
        data = policy.read_json(self.index)
        entries = data.get("entries") if isinstance(data.get("entries"), list) else []
        self.entries = [entry for entry in entries if isinstance(entry, dict)
                        and isinstance(entry.get("id"), str) and ENTRY.fullmatch(entry["id"])
                        and entry.get("kind") in KINDS]
        self.enforce()

    def save(self):
        if self.mode == "session":
            return
        try:
            self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            handle, temporary = tempfile.mkstemp(prefix=".changes-", dir=self.directory)
            with os.fdopen(handle, "wb") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(encode({"version": 1, "entries": self.entries}))
            os.replace(temporary, self.index)
        except OSError as error:
            LOG.warning("could not save the change log: %s", error)

    def _store_blob(self, name, data):
        """Keeps a pre-image; in memory only when nothing is saved."""
        if self.mode == "session":
            self.blobs[name] = data
            return
        try:
            folder = self.directory / "blobs"
            folder.mkdir(parents=True, exist_ok=True, mode=0o700)
            handle, temporary = tempfile.mkstemp(prefix=".blob-", dir=folder)
            with os.fdopen(handle, "wb") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(data)
            os.replace(temporary, self._blob_path(name))
        except OSError as error:
            LOG.warning("could not keep a file for undo: %s", error)
            self.blobs[name] = data

    def _read_blob(self, name):
        if name in self.blobs:
            return self.blobs[name]
        try:
            return self._blob_path(name).read_bytes()
        except OSError:
            return None

    def _drop_blobs(self, entry):
        for name in self._blob_names(entry):
            self.blobs.pop(name, None)
            with contextlib.suppress(OSError):
                self._blob_path(name).unlink()

    @staticmethod
    def _blob_names(entry):
        files = entry.get("files") if isinstance(entry.get("files"), list) else []
        return [item["blob"] for item in files if isinstance(item, dict) and isinstance(item.get("blob"), str)]

    def enforce(self):
        """Applies the retention setting; returns whether anything was dropped."""
        previous, self.mode = self.mode, retention(self.read_settings())
        cutoff = now_ms() - MONTH_MS
        keep = []
        dropped = False
        for index, entry in enumerate(sorted(self.entries, key=lambda item: item.get("at", 0), reverse=True)):
            if index >= MAX_ENTRIES or (self.mode == "month" and entry.get("at", 0) < cutoff):
                self._drop_blobs(entry)
                dropped = True
            else:
                keep.append(entry)
        self.entries = list(reversed(keep))
        if self.mode == "session":
            for entry in self.entries:
                for name in self._blob_names(entry):
                    if name not in self.blobs:
                        data = self._read_blob(name)
                        if data is not None:
                            self.blobs[name] = data
            with contextlib.suppress(OSError):
                self.index.unlink()
            folder = self.directory / "blobs"
            if folder.is_dir():
                for path in folder.iterdir():
                    with contextlib.suppress(OSError):
                        path.unlink()
        elif previous == "session" or dropped:
            for name, data in list(self.blobs.items()):
                self._store_blob(name, data)
                self.blobs.pop(name, None)
            self.save()
        return dropped

    def clear(self):
        for entry in self.entries:
            self._drop_blobs(entry)
        self.entries = []
        self.blobs = {}
        with contextlib.suppress(OSError):
            self.index.unlink()
        folder = self.directory / "blobs"
        if folder.is_dir():
            for path in folder.iterdir():
                with contextlib.suppress(OSError):
                    path.unlink()

    def forget_conversation(self, conversation):
        """A deleted conversation's changes stay undoable; only the link goes."""
        changed = False
        for entry in self.entries:
            if entry.get("conversation") == conversation:
                entry["conversation"] = None
                changed = True
        if changed:
            self.save()

    # ---- recording ---------------------------------------------------------

    def _new(self, turn, kind, target, **fields):
        entry = {"id": "ch-" + secrets.token_hex(8), "turn": turn.id, "conversation": turn.conversation,
                 "question": " ".join(str(turn.prompt or "").split())[:200], "at": now_ms(),
                 "kind": kind, "target": target, "state": "applied"}
        entry.update(fields)
        return entry

    def _file_record(self, entry_id, index, path, before, after):
        record = {"path": path, "afterHash": state_digest(after),
                  "op": "created" if before is None else "deleted" if after is None else "modified"}
        if before is not None:
            name = f"{entry_id}-{index}.bin"
            self._store_blob(name, before[0])
            record["blob"] = name
            record["mode"] = before[1]
        return record

    def from_snapshots(self, turn, snapshots):
        """Entries for what the turn's watched files show; added to the log."""
        added = []
        plugins = {}
        for path in sorted(snapshots.after):
            before, after = snapshots.before.get(path), snapshots.after[path]
            if path == str(self.settings_path):
                old, new = parse_settings(before), parse_settings(after)
                if old is not None and new is not None:
                    for key, had, old_value, has, new_value in setting_diff(old, new):
                        added.append(self._new(turn, "setting", "setting:" + key, key=key, hadBefore=had,
                                               before=old_value, hasAfter=has, after=new_value))
                    continue
            plugin = plugin_of(path, self.home)
            if plugin:
                plugins.setdefault(plugin, []).append((path, before, after))
                continue
            entry = self._new(turn, "file", "file:" + path, path=policy.display(path, self.home))
            entry["files"] = [self._file_record(entry["id"], 0, path, before, after)]
            added.append(entry)
        for plugin, items in sorted(plugins.items()):
            manifest = policy.read_json(os.path.join(self.home, PLUGINS, plugin, "manifest.json"))
            name = manifest.get("name") if isinstance(manifest.get("name"), str) else plugin
            created = all(before is None for _, before, _ in items)
            entry = self._new(turn, "plugin", "plugin:" + plugin, plugin=manifest.get("id") or plugin,
                              name=policy.clip(name, 80), op="created" if created else "modified",
                              path=policy.display(os.path.join(self.home, PLUGINS, plugin), self.home))
            entry["files"] = [self._file_record(entry["id"], index, path, before, after)
                              for index, (path, before, after) in enumerate(items)]
            added.append(entry)
        self.entries.extend(added)
        return added

    def add(self, turn, kind, target, **fields):
        entry = self._new(turn, kind, target, **fields)
        self.entries.append(entry)
        return entry

    # ---- reading -----------------------------------------------------------

    def get(self, identifier):
        return next((entry for entry in self.entries if entry["id"] == identifier), None)

    def current_settings(self):
        return read_settings_file(self.settings_path)

    def _holds(self, entry, settings, exists):
        """Whether what the entry changed still holds the value it left."""
        kind = entry["kind"]
        if kind == "setting":
            if settings is None:
                return False
            if entry.get("hasAfter"):
                return entry["key"] in settings and settings[entry["key"]] == entry.get("after")
            return entry["key"] not in settings
        if kind in ("file", "plugin"):
            for item in entry.get("files") or []:
                if state_digest(policy.file_state(item["path"])) != item.get("afterHash"):
                    return False
            return True
        if kind == "routine":
            return exists("routine", entry.get("routine", {}).get("id"), entry.get("op"))
        if kind == "app":
            return exists("app", entry.get("app", {}).get("id"), entry.get("op"))
        return False

    def summaries(self, exists=None, turn=None):
        """Every entry, newest first, with whether it can be undone now.

        status: applied (undoable), undone, blocked (a later change to the
        same thing comes first: blockedBy), changed (changed since by
        something else), system (Software Update owns it)."""
        exists = exists or (lambda kind, identifier, op: True)
        settings = self.current_settings()
        rows = []
        later = {}
        for entry in reversed(self.entries):
            row = {key: value for key, value in entry.items() if key != "files"}
            row["path"] = entry.get("path", "")
            if entry["kind"] == "system":
                row["status"] = "system"
            elif entry["state"] == "undone":
                row["status"] = "undone"
            elif entry["target"] in later:
                row["status"] = "blocked"
                row["blockedBy"] = later[entry["target"]]
            elif self._holds(entry, settings, exists):
                row["status"] = "applied"
            else:
                row["status"] = "changed"
            row["undoable"] = row["status"] == "applied"
            if entry["state"] == "applied" and entry["kind"] != "system":
                later.setdefault(entry["target"], {"id": entry["id"], "at": entry["at"]})
            if turn is None or entry["turn"] == turn:
                rows.append(row)
        return rows

    # ---- undo --------------------------------------------------------------

    def undo_local(self, entry):
        """Undoes a setting, file or plugin entry. Returns "" or why it was left alone."""
        if entry["kind"] == "setting":
            settings = self.current_settings()
            if settings is None:
                return "Your settings file could not be read."
            if entry.get("hadBefore"):
                settings[entry["key"]] = entry.get("before")
            else:
                settings.pop(entry["key"], None)
            data = (json.dumps(settings, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
            try:
                mode = os.stat(self.settings_path).st_mode & 0o7777
            except OSError:
                mode = 0o644
            try:
                policy.write_atomic(str(self.settings_path), data, mode)
            except OSError as error:
                return str(error)
            return ""
        plugins = os.path.join(self.home, PLUGINS)
        for item in entry.get("files") or []:
            path = item["path"]
            try:
                if item.get("blob"):
                    data = self._read_blob(item["blob"])
                    if data is None:
                        return "The earlier version is no longer kept."
                    policy.write_atomic(path, data, item.get("mode", 0o644))
                else:
                    with contextlib.suppress(FileNotFoundError):
                        os.unlink(path)
                    parent = os.path.dirname(path)
                    while policy.under(parent, plugins) and parent != plugins:
                        try:
                            os.rmdir(parent)
                        except OSError:
                            break
                        parent = os.path.dirname(parent)
            except OSError as error:
                return str(error)
        return ""

    def mark_undone(self, entry):
        entry["state"] = "undone"
        entry["undoneAt"] = now_ms()
        self._drop_blobs(entry)
        self.save()

