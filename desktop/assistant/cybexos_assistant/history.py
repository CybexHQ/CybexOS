"""Wiz's conversation history: one JSON file per conversation.

A conversation is the questions asked in one box, their answers, and the
agent session that continues them. Records live in memory while the service
runs and are written to `conversations/<id>.json` under the state directory
(0700, files 0600), unless the person chose not to save them
(`assistantHistory: "session"` in shell.json). Old ones are pruned after 30
days by default. Screenshots and approval cards are never stored.
"""

from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import re
import secrets
import tempfile

from .protocol import LOG, encode, now_ms


RETENTION = ("month", "forever", "session")
DEFAULT_RETENTION = "month"
MONTH_MS = 30 * 24 * 3600 * 1000
# A bound on memory and on the list a client receives; the oldest go first.
MAX_CONVERSATIONS = 500
MAX_TITLE = 200
MAX_PREVIEW = 200
CONVERSATION = re.compile(r"^c-[0-9a-f]{16}$")
SESSION = re.compile(r"^[A-Za-z0-9._:-]{1,200}$")
AGENTS = ("claude", "codex")
STATUSES = ("running", "waiting", "completed", "stopped", "failed")
TURN = re.compile(r"^t-[0-9a-f]{1,64}$")


def collapse(text, limit):
    """One line, at most `limit` characters, for titles and previews."""
    value = " ".join(str(text or "").split())
    return value if len(value) <= limit else value[:limit - 1].rstrip() + "…"


def retention(settings):
    value = settings.get("assistantHistory") if isinstance(settings, dict) else None
    return value if value in RETENTION else DEFAULT_RETENTION


def _turn(entry):
    """A stored turn, or None when it is not one."""
    if not isinstance(entry, dict) or not isinstance(entry.get("id"), str) or not TURN.fullmatch(entry["id"]):
        return None
    status = entry.get("status") if entry.get("status") in STATUSES else "failed"
    return {
        "id": entry["id"], "prompt": str(entry.get("prompt") or ""), "text": str(entry.get("text") or ""),
        "status": status, "error": str(entry.get("error") or ""), "errorKind": str(entry.get("errorKind") or ""),
        "startedAt": int(entry.get("startedAt") or 0), "finishedAt": int(entry.get("finishedAt") or 0),
    }


def _record(document):
    """A stored conversation, or None when the file is not one."""
    if not isinstance(document, dict):
        return None
    identifier, agent = document.get("id"), document.get("agent")
    if not isinstance(identifier, str) or not CONVERSATION.fullmatch(identifier) or agent not in AGENTS:
        return None
    session = document.get("session")
    turns = [turn for turn in map(_turn, document.get("turns") or []) if turn is not None] \
        if isinstance(document.get("turns"), list) else []
    if not turns:
        return None
    return {
        "id": identifier, "agent": agent,
        "session": session if isinstance(session, str) and SESSION.fullmatch(session) else None,
        "title": collapse(document.get("title") or turns[0]["prompt"], MAX_TITLE),
        "createdAt": int(document.get("createdAt") or turns[0]["startedAt"] or 0),
        "updatedAt": int(document.get("updatedAt") or turns[-1]["startedAt"] or 0),
        "turns": turns,
    }


class History:
    def __init__(self, directory, read_settings):
        self.directory = Path(directory)
        self.read_settings = read_settings
        self.records = {}
        # The one conversation deleted last, for Undo.
        self.deleted = None
        self.mode = DEFAULT_RETENTION

    # ---- storage -----------------------------------------------------------

    def load(self, interrupted):
        """Reads every stored conversation. A turn that was still running when
        the service stopped is marked with `interrupted` (status, error, kind)."""
        self.mode = retention(self.read_settings())
        if not self.directory.is_dir():
            return
        for path in self.directory.glob("c-*.json"):
            try:
                record = _record(json.loads(path.read_text(encoding="utf-8")))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                record = None
            if record is None or path.name != record["id"] + ".json":
                LOG.warning("ignoring an unreadable conversation: %s", path.name)
                continue
            last = record["turns"][-1]
            if last["status"] in ("running", "waiting"):
                last["status"], last["error"], last["errorKind"] = interrupted
                last["finishedAt"] = last["finishedAt"] or now_ms()
            self.records[record["id"]] = record
        self.enforce()

    def _path(self, identifier):
        return self.directory / (identifier + ".json")

    def write(self, record):
        if self.mode == "session" or record["id"] not in self.records:
            return
        try:
            self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            handle, temporary = tempfile.mkstemp(prefix=".conversation-", dir=self.directory)
            with os.fdopen(handle, "wb") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(encode(record))
            os.replace(temporary, self._path(record["id"]))
        except OSError as error:
            LOG.warning("could not save a conversation: %s", error)

    def _unlink(self, identifier):
        with contextlib.suppress(OSError):
            self._path(identifier).unlink()

    def enforce(self, keep=None):
        """Applies the retention setting: forgets conversations past 30 days
        (or over the limit) and, for "session", removes the stored files.
        `keep` (a conversation id) is never removed: a turn is running in it.
        Returns whether the list changed."""
        previous, self.mode = self.mode, retention(self.read_settings())
        changed = False
        cutoff = now_ms() - MONTH_MS
        newest = sorted(self.records.values(), key=lambda record: record["updatedAt"], reverse=True)
        for index, record in enumerate(newest):
            if record["id"] == keep:
                continue
            if index >= MAX_CONVERSATIONS or (self.mode == "month" and record["updatedAt"] < cutoff):
                del self.records[record["id"]]
                self._unlink(record["id"])
                changed = True
        if self.mode == "session" and self.directory.is_dir():
            for path in self.directory.glob("c-*.json"):
                with contextlib.suppress(OSError):
                    path.unlink()
        elif previous == "session" and self.mode != "session":
            # Saving again: what is in memory goes to disk from now on.
            for record in self.records.values():
                self.write(record)
        return changed

    # ---- changes -----------------------------------------------------------

    def create(self, agent):
        identifier = "c-" + secrets.token_hex(8)
        stamp = now_ms()
        record = {"id": identifier, "agent": agent, "session": None, "title": "", "createdAt": stamp,
                  "updatedAt": stamp, "turns": []}
        self.records[identifier] = record
        return record

    def get(self, identifier):
        return self.records.get(identifier) if isinstance(identifier, str) else None

    def begin(self, record, turn):
        """A question asked in `record`; written before the agent starts."""
        if not record["turns"]:
            record["title"] = collapse(turn.prompt, MAX_TITLE)
        record["turns"].append(self.entry(turn))
        record["updatedAt"] = turn.started_at
        self.write(record)

    def finish(self, record, turn):
        """The answer to the record's last question."""
        for index in range(len(record["turns"]) - 1, -1, -1):
            if record["turns"][index]["id"] == turn.id:
                record["turns"][index] = self.entry(turn)
                break
        record["updatedAt"] = max(record["updatedAt"], turn.finished_at or now_ms())
        self.write(record)

    def set_session(self, record, session):
        value = session if isinstance(session, str) and SESSION.fullmatch(session) else None
        if record.get("session") != value:
            record["session"] = value
            self.write(record)

    def delete(self, identifier):
        record = self.records.pop(identifier, None)
        if record is None:
            return None
        self._unlink(identifier)
        self.deleted = record
        return record

    def restore(self, identifier):
        record = self.deleted
        if record is None or record["id"] != identifier:
            return None
        self.deleted = None
        self.records[identifier] = record
        self.write(record)
        return record

    def clear(self):
        self.records = {}
        self.deleted = None
        if self.directory.is_dir():
            for path in list(self.directory.glob("c-*.json")) + list(self.directory.glob(".conversation-*")):
                with contextlib.suppress(OSError):
                    path.unlink()

    # ---- reading -----------------------------------------------------------

    @staticmethod
    def entry(turn):
        return {"id": turn.id, "prompt": turn.prompt, "text": turn.text, "status": turn.status,
                "error": turn.error, "errorKind": turn.error_kind, "startedAt": turn.started_at,
                "finishedAt": turn.finished_at}

    @staticmethod
    def matches(record, query):
        if not query:
            return True
        needle = query.casefold()
        return needle in record["title"].casefold() or any(
            needle in turn["prompt"].casefold() or needle in turn["text"].casefold() for turn in record["turns"])

    @staticmethod
    def summary(record, live=None):
        """A row for the history list. `live` is the running turn's snapshot
        when it belongs to this conversation, for its current status."""
        last = record["turns"][-1] if record["turns"] else None
        status = last["status"] if last else "completed"
        preview = (last["error"] if status == "failed" else last["text"]) if last else ""
        if live is not None and live.get("id") == (last or {}).get("id"):
            status = live.get("status", status)
            if status in ("running", "waiting"):
                preview = live.get("step") or preview
        return {"id": record["id"], "agent": record["agent"], "title": record["title"],
                "preview": collapse(preview, MAX_PREVIEW), "status": status, "turns": len(record["turns"]),
                "createdAt": record["createdAt"], "updatedAt": record["updatedAt"]}

    def summaries(self, query="", live=None):
        rows = sorted(self.records.values(), key=lambda record: record["updatedAt"], reverse=True)
        return [self.summary(record, live if live and live.get("conversation") == record["id"] else None)
                for record in rows if self.matches(record, query)]
