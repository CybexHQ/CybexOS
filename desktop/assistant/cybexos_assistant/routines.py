"""Routines: questions Wiz asks on a schedule (docs/assistant.md).

The person creates one by asking ("every Monday morning, check this
computer"), through the routine_create desktop tool, or in Settings →
Assistant. A routine runs only while they are logged in, because this
service runs in their session; a run missed while the computer was off or
nobody was logged in happens once, at the next chance. A routine only looks:
its turn may not change anything, and fixes wait in its conversation.

Stored in `routines.json` beside the conversations (0600). Routines are the
person's own setup, so they are kept whatever `assistantHistory` says; their
runs are ordinary conversations and follow it.
"""

from __future__ import annotations

import datetime
import os
from pathlib import Path
import re
import secrets
import tempfile

from . import policy
from .protocol import LOG, encode, now_ms


ROUTINE = re.compile(r"^r-[0-9a-f]{12}$")
KINDS = ("daily", "weekly", "monthly", "update")
NOTIFY = ("attention", "always")
TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
MAX_ROUTINES = 20
MAX_QUESTION = 2000
MAX_TITLE = 80
# The first line of a routine's reply says whether it needs the person.
ATTENTION = re.compile(r"^\s*\**ATTENTION:\s*(yes|no)\**\s*$", re.I)


def schedule_error(schedule):
    if not isinstance(schedule, dict) or schedule.get("kind") not in KINDS:
        return "The schedule must be daily, weekly, monthly or update."
    if schedule["kind"] != "update" and not TIME.fullmatch(str(schedule.get("time", ""))):
        return "The time must be HH:MM, for example 09:00."
    if schedule["kind"] == "weekly" and not (isinstance(schedule.get("weekday"), int)
                                            and 0 <= schedule["weekday"] <= 6):
        return "A weekly routine needs a weekday from 0 (Monday) to 6 (Sunday)."
    if schedule["kind"] == "monthly" and not (isinstance(schedule.get("day"), int) and 1 <= schedule["day"] <= 28):
        return "A monthly routine needs a day from 1 to 28."
    return ""


def clean_schedule(schedule):
    kind = schedule["kind"]
    clean = {"kind": kind}
    if kind != "update":
        clean["time"] = schedule["time"]
    if kind == "weekly":
        clean["weekday"] = schedule["weekday"]
    if kind == "monthly":
        clean["day"] = schedule["day"]
    return clean


def due_after(schedule, after):
    """The first scheduled moment strictly after `after` (a local datetime),
    or None for a routine that follows updates."""
    kind = schedule.get("kind")
    if kind == "update":
        return None
    hour, minute = (int(part) for part in schedule["time"].split(":"))
    candidate = after.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if kind == "daily":
        if candidate <= after:
            candidate += datetime.timedelta(days=1)
        return candidate
    if kind == "weekly":
        candidate += datetime.timedelta(days=(schedule["weekday"] - candidate.weekday()) % 7)
        if candidate <= after:
            candidate += datetime.timedelta(days=7)
        return candidate
    candidate = candidate.replace(day=schedule["day"])
    if candidate <= after:
        month = candidate.month + 1
        candidate = candidate.replace(year=candidate.year + (month > 12), month=(month - 1) % 12 + 1)
    return candidate


def to_local(ms):
    return datetime.datetime.fromtimestamp(ms / 1000)


def to_ms(moment):
    return int(moment.timestamp() * 1000)


def split_attention(text):
    """(needs attention, the reply without its ATTENTION line)."""
    lines = str(text or "").split("\n")
    for index, line in enumerate(lines[:3]):
        match = ATTENTION.match(line)
        if match:
            rest = "\n".join(lines[:index] + lines[index + 1:]).strip()
            return match.group(1).lower() == "yes", rest
    return None, str(text or "").strip()


class Routines:
    def __init__(self, path):
        self.path = Path(path)
        self.items = []

    def load(self):
        data = policy.read_json(self.path)
        items = data.get("routines") if isinstance(data.get("routines"), list) else []
        self.items = []
        for item in items:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str) or not ROUTINE.fullmatch(item["id"]):
                continue
            if not isinstance(item.get("question"), str) or schedule_error(item.get("schedule")):
                continue
            item.setdefault("enabled", True)
            item.setdefault("notify", "attention")
            self.items.append(item)

    def save(self):
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            handle, temporary = tempfile.mkstemp(prefix=".routines-", dir=self.path.parent)
            with os.fdopen(handle, "wb") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(encode({"version": 1, "routines": self.items}))
            os.replace(temporary, self.path)
        except OSError as error:
            LOG.warning("could not save routines: %s", error)

    def get(self, identifier):
        return next((item for item in self.items if item["id"] == identifier), None)

    @staticmethod
    def _check(question, title, schedule, notify):
        if not isinstance(question, str) or not question.strip():
            return "A routine needs a question."
        if len(question) > MAX_QUESTION:
            return "That question is too long for a routine."
        if title is not None and not isinstance(title, str):
            return "The title must be text."
        if notify is not None and notify not in NOTIFY:
            return "notify is attention or always."
        return schedule_error(schedule)

    def create(self, question, schedule, title=None, notify=None, agent=None, version=""):
        """(routine, "") or (None, why not)."""
        error = self._check(question, title, schedule, notify)
        if error:
            return None, error
        if len(self.items) >= MAX_ROUTINES:
            return None, f"There are already {MAX_ROUTINES} routines. Remove one first."
        question = question.strip()
        stamp = now_ms()
        routine = {
            "id": "r-" + secrets.token_hex(6),
            "title": " ".join((title or question).split())[:MAX_TITLE],
            "question": question, "schedule": clean_schedule(schedule),
            "notify": notify or "attention", "enabled": True,
            "agent": agent if agent in ("claude", "codex") else None,
            "createdAt": stamp, "lastRun": 0, "version": version, "last": None,
        }
        self.items.append(routine)
        self.save()
        return routine, ""

    def update(self, identifier, changes):
        routine = self.get(identifier)
        if routine is None:
            return None, "That routine no longer exists."
        merged = dict(routine)
        for key in ("question", "title", "notify", "enabled", "schedule"):
            if key in changes:
                merged[key] = changes[key]
        if not isinstance(merged.get("enabled"), bool):
            return None, "enabled is true or false."
        error = self._check(merged["question"], merged.get("title"), merged["schedule"], merged["notify"])
        if error:
            return None, error
        merged["question"] = merged["question"].strip()
        merged["title"] = " ".join((merged.get("title") or merged["question"]).split())[:MAX_TITLE]
        merged["schedule"] = clean_schedule(merged["schedule"])
        if merged["schedule"] != routine["schedule"]:
            # A new schedule counts from now, not from the last run.
            merged["lastRun"] = now_ms()
        routine.clear()
        routine.update(merged)
        self.save()
        return routine, ""

    def delete(self, identifier):
        routine = self.get(identifier)
        if routine is None:
            return None
        self.items.remove(routine)
        self.save()
        return routine

    def due(self, now, version=""):
        """The enabled routines whose time has come, oldest first."""
        found = []
        for routine in self.items:
            if not routine.get("enabled"):
                continue
            schedule = routine["schedule"]
            if schedule["kind"] == "update":
                if version and routine.get("version") and version != routine["version"]:
                    found.append(routine)
                elif version and not routine.get("version"):
                    routine["version"] = version
                continue
            since = routine.get("lastRun") or routine.get("createdAt") or now
            moment = due_after(schedule, to_local(since))
            if moment is not None and to_ms(moment) <= now:
                found.append(routine)
        return found

    def ran(self, routine, version, result):
        routine["lastRun"] = now_ms()
        if version:
            routine["version"] = version
        routine["last"] = result
        self.save()

    def next_run(self, routine, now):
        if routine["schedule"]["kind"] == "update" or not routine.get("enabled"):
            return 0
        since = max(routine.get("lastRun") or 0, routine.get("createdAt") or 0) or now
        moment = due_after(routine["schedule"], to_local(since))
        return to_ms(moment) if moment else 0

    def summaries(self, now=None):
        now = now or now_ms()
        return [dict(routine, next=self.next_run(routine, now)) for routine in self.items]
