"""One question and its answer: streamed text, steps and approval cards."""

from __future__ import annotations

import asyncio
import re

from . import policy, steps
from .protocol import now_ms


FINAL = ("completed", "stopped", "failed")
STOPPED_MESSAGE = "The person stopped this request."
DECLINED_MESSAGE = ("The person declined this action. Do not retry it; explain what you wanted "
                    "to do so they can decide.")
LOOK_ONLY_MESSAGE = ("This question may only look, because another one is still running. Say in one "
                     "sentence what you would change and stop; Cybex OS asks it again, with changes "
                     "allowed, when the other one is done.")
ROUTINE_MESSAGE = ("A routine only looks. Do not change anything; describe the fix so the person can "
                   "ask for it.")
AUTH_PATTERN = re.compile(r"\b(?:log ?in|/login|logged in|authenticat\w*|api key|401|oauth|unauthori[sz]ed|sign in)\b", re.I)


def classify(error):
    return "auth" if error and AUTH_PATTERN.search(str(error)) else ""


def looks(decision):
    """Whether an allowed action only reads: no file it may write, and not a
    staged system change (whose step waits for the administrator)."""
    return decision.action == "allow" and not decision.paths and not decision.step and not decision.changes


class Turn:
    def __init__(self, identifier, agent, prompt, home, memory, publish, screenshot=False,
                 approval_policy="always", conversation=None, lane="main", look_only=False, routine=None,
                 queued=False):
        self.id = identifier
        self.agent = agent
        # The history entry this question belongs to (history.py).
        self.conversation = conversation
        self.prompt = prompt
        self.status = "running"
        self.step = "Thinking"
        self.text = ""
        self.error = ""
        self.error_kind = ""
        self.started_at = now_ms()
        self.finished_at = 0
        self.undo = []
        self.plugins = []
        self.staged = ""
        self.screenshot = screenshot
        self.snapshots = policy.Snapshots(home)
        # Conversation-wide "always" answers, shared with the next turns.
        self.memory = memory
        self.approval_policy = approval_policy
        self.stopping = False
        # "main", or "side": a question asked while the main one runs, which
        # may only look (look_only). A routine's run looks only too.
        self.lane = lane
        self.look_only = look_only or bool(routine)
        self.routine = routine
        self.queued = queued
        # A look-only question that wanted to change something: it runs
        # again in the main lane afterwards (server.py).
        self.needs_change = False
        # A routine's verdict: whether its findings need the person.
        self.attention = None
        # "What Wiz did": one entry per tool (steps.py).
        self.steps = []
        # Routines this question created, for the reply's card.
        self.routines = []
        self._publish = publish
        self._approvals = {}
        self._counter = 0

    @property
    def finished(self):
        return self.status in FINAL

    def snapshot(self, resumable=False, changes=None):
        changes = list(changes or [])
        return {
            "id": self.id, "agent": self.agent, "prompt": self.prompt, "status": self.status,
            "step": self.step, "text": self.text, "error": self.error, "errorKind": self.error_kind,
            "approvals": [entry["card"] for entry in self._approvals.values()],
            "startedAt": self.started_at, "finishedAt": self.finished_at,
            # The files and preferences Undo would restore (what `changes` can undo now).
            "undo": sorted({row.get("path") or "~/.config/cybexos/shell.json" for row in changes
                            if row.get("undoable") and row.get("kind") in ("setting", "file", "plugin")}),
            "changes": changes, "steps": list(self.steps), "routines": list(self.routines),
            "plugins": list(self.plugins), "staged": self.staged, "screenshot": self.screenshot,
            "resumable": resumable, "conversation": self.conversation, "lane": self.lane,
            "lookOnly": self.look_only, "needsChange": self.needs_change,
            "routine": self.routine, "attention": self.attention, "queued": self.queued,
        }

    def add_step(self, entry):
        """Records one tool use for the step list; a repeat of the last is skipped."""
        if not entry or self.finished or len(self.steps) >= steps.MAX_STEPS:
            return
        if self.steps and self.steps[-1] == entry:
            return
        self.steps.append(entry)

    def updated(self):
        self._publish("updated", self)

    def delta(self, text):
        if text and not self.finished:
            self.text += text
            self._publish("delta", self, text)

    def reset_text(self):
        if self.text and not self.finished:
            self.text = ""
            self.updated()

    def set_step(self, step):
        if step and step != self.step and not self.finished and self.status != "waiting":
            self.step = step
            self.updated()

    def finish(self, status, text=None, error="", kind=""):
        self.status = status
        if text is not None:
            self.text = text
        self.error = error or ""
        self.error_kind = kind or (classify(error) if status == "failed" else "")
        self.step = ""
        self.finished_at = now_ms()
        self.deny_all()

    # ---- approvals ---------------------------------------------------------

    async def authorize(self, decision, cancel_key=None):
        """("allow" | "always" | "deny" | "cancelled", message for a denial)."""
        if decision.action == "deny":
            return "deny", decision.message
        if self.stopping or self.finished:
            return "deny", STOPPED_MESSAGE
        if self.look_only and not looks(decision):
            if not self.needs_change:
                self.needs_change = True
                self.updated()
            return "deny", ROUTINE_MESSAGE if self.routine else LOOK_ONLY_MESSAGE
        if decision.action == "ask" and (self.approval_policy == "ask" or decision.always) \
                and not (decision.key and decision.key in self.memory):
            answer = await self.ask(decision.card, cancel_key)
            if answer == "cancelled":
                return "cancelled", ""
            if answer not in ("allow", "always"):
                return "deny", STOPPED_MESSAGE if self.stopping else DECLINED_MESSAGE
            if answer == "always" and decision.key:
                self.memory.add(decision.key)
            result = answer
        else:
            result = "allow"
        for path in decision.paths:
            self.snapshots.take(path)
        if decision.step:
            self.set_step(decision.step)
        return result, ""

    async def ask(self, card, cancel_key=None):
        self._counter += 1
        identifier = f"a-{self._counter}"
        future = asyncio.get_running_loop().create_future()
        self._approvals[identifier] = {"card": dict(card, id=identifier), "future": future, "cancel": cancel_key}
        previous = self.step
        self.status = "waiting"
        self.step = "Waiting for your review" if card.get("kind") == "apply" else "Waiting for your approval"
        self.updated()
        try:
            return await future
        finally:
            self._approvals.pop(identifier, None)
            if not self._approvals and self.status == "waiting":
                self.status = "running"
                self.step = previous or "Working"
            if not self.finished:
                self.updated()

    # Answers leave the card list at once, so the snapshot published for the
    # change never still shows the card that was just answered.
    def _resolve(self, identifier, answer):
        entry = self._approvals.pop(identifier, None)
        if entry is None or entry["future"].done():
            return False
        entry["future"].set_result(answer)
        return True

    def respond(self, identifier, decision):
        return self._resolve(identifier, decision)

    def cancel(self, cancel_key):
        for identifier, entry in list(self._approvals.items()):
            if entry["cancel"] is not None and entry["cancel"] == cancel_key:
                self._resolve(identifier, "cancelled")

    def deny_all(self):
        for identifier in list(self._approvals):
            self._resolve(identifier, "deny")
