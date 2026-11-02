"""The socket, the conversation history and the questions in progress.

The service owns the agent processes so a Quickshell restart, including one
the assistant's own change caused, never ends a turn. Clients reconcile with
`hello`; nothing is replayed after a reconnect. Every question belongs to a
conversation in the history (history.py): `turn.start` names the one it
continues, or starts a new one.

Two questions can be in progress at once (docs/assistant.md). The main lane
runs the question that may change things. A question asked while it runs
goes to the side lane, where it may only look; if it needs a change it waits
in the queue ("Up next") and runs in the main lane once that is free. One
question waits at most. Routines (routines.py) run in the main lane, looking
only, when it is free.

Everything a turn changed is recorded in the change log (changes.py), so it
can be undone from the reply or from Settings later. The desktop tools
(desktop.py, served to the agents by mcp.py) arrive here as `desktop.call`;
the ones only the desktop can carry out go to the shell as `desktop.request`.

Activation never restarts this service (nix/modules/desktop.nix), so an update
the assistant applies cannot end the answer that reports it. When an update
changes the service's own unit, it restarts itself into the new one once it
has been idle for a while (`renewable`), and otherwise at the next login.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import tempfile
import time
import urllib.parse
import urllib.request

from . import auth, desktop, history as history_module, mcp, policy, prompt, routines, speech, steps
from .changes import ChangeLog
from .claude import ClaudeAgent, media_type
from .codex import CodexAgent
from .history import History
from .protocol import (
    BUSY, LOG, MAX_CLIENT_BACKLOG, MAX_LINE, MAX_PROMPT, MAX_SCREENSHOT, NOT_FOUND, PROTOCOL,
    UNAVAILABLE, RpcFault, default_state_dir, encode, error_frame, iter_lines, notification,
    now_ms, parse_json, result_frame, screenshot_dir,
)
from .turn import FINAL, Turn


AGENTS = {"claude": ClaudeAgent, "codex": CodexAgent}
LABELS = {"claude": "Claude Code", "codex": "Codex"}
DISCOVERY_SECONDS = 30.0
STOP_WAIT = 8.0
MODEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/\[\]-]{0,79}$")
LANGUAGE = re.compile(r"^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})?$")
RESTARTED = "The assistant service restarted."
LANES = ("main", "side")
MAX_ATTACHMENTS = 8
MAX_FILE = 256 * 1024
ATTACHMENT_KINDS = ("window", "selection", "file", "image", "text")
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".gif")
SHELL_TIMEOUT = 30.0
# Downloading a wallpaper takes longer than flipping a setting.
SHELL_SLOW_TIMEOUT = 180.0
FLATHUB_TIMEOUT = 900.0
ROUTINE_TICK = 30.0
# Renewal after an update changed this service's unit: how often to look, how
# long nothing must have run first, and the exit status systemd answers with
# a start of the new unit (RestartForceExitStatus in nix/modules/desktop.nix).
UNIT = "/etc/systemd/user/cybexos-assistant.service"
RENEW_TICK = 5.0
RENEW_QUIET = 120.0
RENEW_EXIT = 75
WALLHAVEN = "https://wallhaven.cc/api/v1"


class DesktopError(Exception):
    pass


def turn_context(value):
    """turn.start's context for the per-turn note; an unknown purpose is dropped."""
    value = value if isinstance(value, dict) else {}
    context = {key: value[key] for key in ("output", "speak", "language", "wide") if key in value}
    if isinstance(value.get("purpose"), str) and value["purpose"] in prompt.PURPOSE_NOTES:
        context["purpose"] = value["purpose"]
    return context


class Client:
    """One connection; frames are queued so a slow reader never blocks the others."""

    def __init__(self, writer):
        self.writer = writer
        self.queue = asyncio.Queue()
        self.closed = False
        # What the client called itself in hello: "quickshell" is the shell,
        # which carries out the desktop tools only it can.
        self.kind = ""
        self.task = asyncio.create_task(self._write())

    def send(self, frame):
        if self.closed:
            return
        if self.queue.qsize() >= MAX_CLIENT_BACKLOG:
            LOG.warning("disconnecting a client that stopped reading")
            self.close()
            return
        self.queue.put_nowait(frame)

    async def _write(self):
        try:
            while True:
                frame = await self.queue.get()
                self.writer.write(frame)
                await self.writer.drain()
        except (ConnectionError, OSError):
            self.close()

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.task.cancel()
        with contextlib.suppress(Exception):
            self.writer.close()


def unit_identity(path):
    """The store file the user unit resolves to. NixOS links each unit to its
    own store path, so the identity changes exactly when its text does."""
    try:
        return os.path.realpath(path, strict=True)
    except (OSError, ValueError):
        return None


class Lane:
    """One question in progress at most, its agents and its conversation."""

    def __init__(self, name):
        self.name = name
        self.turn = None
        self.task = None
        # The conversation of the turn in progress, which receives the
        # agent's session id.
        self.active = None
        self.adapters = {}

    def busy(self):
        return self.task is not None and not self.task.done()


class Server:
    def __init__(self, socket_path, state_dir=None, home=None, env=None):
        self.env = dict(os.environ if env is None else env)
        self.home = Path(home or self.env.get("HOME") or Path.home())
        config = Path(self.env.get("XDG_CONFIG_HOME") or self.home / ".config")
        self.settings_path = config / "cybexos" / "shell.json"
        self.socket_path = Path(socket_path)
        state = Path(state_dir or default_state_dir(self.home))
        self.state_path = state / "state.json"
        read_settings = lambda: policy.read_json(self.settings_path)  # noqa: E731
        self.history = History(state / "conversations", read_settings)
        self.changes = ChangeLog(state / "changes", read_settings, self.home, self.settings_path)
        self.routines = routines.Routines(state / "routines.json")
        self.status_path = self.env.get("CYBEXOS_ASSISTANT_STATUS") or "/var/lib/cybexos/status.json"
        self.release_path = self.env.get("CYBEXOS_ASSISTANT_RELEASE") or "/etc/cybexos/release.json"
        self.shots = screenshot_dir(self.env)
        self.instructions = prompt.build()
        self.clients = set()
        self.tasks = set()
        self.lanes = {name: Lane(name) for name in LANES}
        # "Always in this conversation" answers, per conversation.
        self.memories = {}
        # The question waiting for the main lane ("Up next"), or None.
        self.queue = None
        # Routines whose time came while the main lane was busy.
        self.waiting_routines = []
        self.desktop_pending = {}
        self.wallpapers = {}
        self.discovered = (0.0, {})
        self.authentication = {}
        self.auth_lock = asyncio.Lock()
        self.speaker = speech.Speaker(speech.default_socket(self.env), self.publish)
        self.listener = None
        self.scheduler = None
        self.closing = False
        # The unit this process runs, and when a question last started or ended.
        self.unit_path = self.env.get("CYBEXOS_ASSISTANT_UNIT") or UNIT
        self.unit = unit_identity(self.unit_path)
        self.quiet_since = time.monotonic()
        self.stopping = None
        self.renewing = False
        self.methods = {
            "hello": self.hello, "turn.start": self.turn_start, "turn.stop": self.turn_stop,
            "approval.respond": self.approval_respond, "turn.undo": self.turn_undo,
            "conversation.list": self.conversation_list, "conversation.open": self.conversation_open,
            "conversation.delete": self.conversation_delete, "conversation.restore": self.conversation_restore,
            "conversation.clear": self.conversation_clear, "conversation.handoff": self.conversation_handoff,
            "speech.say": self.speech_say, "speech.stop": self.speech_stop,
            "auth.status": self.auth_status, "auth.login": self.auth_login,
            "queue.remove": self.queue_remove, "queue.run": self.queue_run,
            "change.list": self.change_list, "change.undo": self.change_undo,
            "routine.list": self.routine_list, "routine.create": self.routine_create,
            "routine.update": self.routine_update, "routine.delete": self.routine_delete,
            "routine.run": self.routine_run,
            "desktop.call": self.desktop_call, "desktop.respond": self.desktop_respond,
        }
        self._load()

    # ---- compatibility: the main lane ---------------------------------------

    @property
    def turn(self):
        return self.lanes["main"].turn

    @turn.setter
    def turn(self, value):
        self.lanes["main"].turn = value

    def busy(self, lane="main"):
        return self.lanes[lane].busy()

    # ---- agents ------------------------------------------------------------

    def agent_env(self):
        env = dict(self.env)
        local = str(self.home / ".local" / "bin")
        if local not in env.get("PATH", "").split(os.pathsep):
            env["PATH"] = os.pathsep.join(filter(None, [env.get("PATH", ""), local]))
        return env

    def agents(self):
        stamp, found = self.discovered
        if time.monotonic() - stamp < DISCOVERY_SECONDS and found:
            return found
        found = {}
        search = self.agent_env()["PATH"]
        for name in AGENTS:
            override = self.env.get("CYBEXOS_ASSISTANT_" + name.upper())
            if override:
                found[name] = override if os.path.isfile(override) and os.access(override, os.X_OK) else None
            else:
                found[name] = shutil.which(name, path=search)
        self.discovered = (time.monotonic(), found)
        return found

    def preferred(self):
        config = Path(self.env.get("XDG_CONFIG_HOME") or self.home / ".config")
        try:
            value = (config / "cybexos" / "defaults" / "agent").read_text(encoding="utf-8").strip()
        except (OSError, UnicodeDecodeError):
            return None
        return value if value in AGENTS else None

    def resolve(self, requested, statuses=None):
        if requested in AGENTS:
            return requested
        found = self.agents()
        preferred = self.preferred()
        order = ([preferred] if preferred else []) + list(AGENTS)
        if statuses:
            for name in order:
                if statuses.get(name, {}).get('auth') == 'ready':
                    return name
        for name in order:
            if found.get(name):
                return name
        return preferred or "claude"

    def adapter(self, lane, name, executable):
        adapter = lane.adapters.get(name)
        if adapter is not None and adapter.executable != executable:
            self._spawn(adapter.close())
            adapter = None
        if adapter is None:
            tools = None if self.env.get("CYBEXOS_ASSISTANT_NO_TOOLS") else mcp.command(self.socket_path, lane.name)
            adapter = AGENTS[name](executable, self.home, self.instructions, status_path=self.status_path,
                                   on_conversation=lambda agent, identifier: self._conversation_id(lane, agent, identifier),
                                   env=self.agent_env(), mcp=tools, look_only=lane.name == "side")
            lane.adapters[name] = adapter
        return adapter

    def _conversation_id(self, lane, agent, identifier):
        record = lane.active
        if record is None or record["agent"] != agent:
            return
        self.history.set_session(record, identifier or None)
        if lane.turn is not None:
            self._turn_event("updated", lane.turn)

    async def _close_adapters(self):
        for lane in self.lanes.values():
            adapters, lane.adapters = list(lane.adapters.values()), {}
            for adapter in adapters:
                await adapter.close()

    # ---- notifications -----------------------------------------------------

    def _spawn(self, coroutine):
        task = asyncio.create_task(coroutine)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return task

    def publish(self, method, params):
        frame = encode(notification(method, params))
        for client in list(self.clients):
            client.send(frame)

    def resumable(self, turn):
        record = self.history.get(turn.conversation)
        return bool(record and record["session"] and record["agent"] == turn.agent)

    def summaries(self, query=""):
        live = [self.snapshot(lane.turn) for lane in self.lanes.values() if lane.turn is not None]
        return self.history.summaries(query, live)

    def publish_history(self):
        self.publish("conversations.updated", {"conversations": self.summaries()})

    def _exists(self, kind, identifier, op):
        if kind == "routine":
            present = self.routines.get(identifier) is not None
            return present if op == "created" else not present
        return True

    def snapshot(self, turn):
        if turn is None:
            return None
        return turn.snapshot(self.resumable(turn), changes=self.changes.summaries(self._exists, turn=turn.id))

    def _turn_event(self, kind, turn, text=None):
        lane = self.lanes.get(turn.lane)
        if lane is None or turn is not lane.turn:
            return
        if kind == "delta":
            self.publish("turn.delta", {"id": turn.id, "text": text, "lane": lane.name})
        else:
            self.publish("turn.updated", {"turn": self.snapshot(turn), "lane": lane.name})

    def queue_summary(self):
        if self.queue is None:
            return None
        return {key: self.queue[key] for key in ("id", "text", "conversation", "createdAt", "reason")}

    def publish_queue(self):
        self.publish("queue.updated", {"queue": self.queue_summary()})

    def publish_changes(self):
        self.publish("changes.updated", {"count": len(self.changes.entries)})
        for lane in self.lanes.values():
            if lane.turn is not None:
                self._turn_event("updated", lane.turn)

    def publish_routines(self):
        self.publish("routines.updated", {"routines": self.routines.summaries()})

    # ---- methods -----------------------------------------------------------

    async def hello(self, params):
        return {
            "protocol": PROTOCOL,
            "agents": await self.agent_status(),
            "turn": self.snapshot(self.lanes["main"].turn),
            "side": self.snapshot(self.lanes["side"].turn),
            "queue": self.queue_summary(),
            "conversations": self.summaries(),
            "routines": self.routines.summaries(),
            "speech": {"available": self.speaker.available},
        }

    async def agent_status(self, refresh=False):
        async with self.auth_lock:
            if refresh:
                self.discovered = (0.0, {})
            found = self.agents()
            async def inspect(name):
                executable = found.get(name)
                if not executable:
                    self.authentication.pop(name, None)
                    return name, {"available": False, "label": LABELS[name], "auth": "missing"}
                stamp, previous_executable, state = self.authentication.get(name, (0.0, None, "unknown"))
                if refresh or previous_executable != executable or time.monotonic() - stamp >= DISCOVERY_SECONDS:
                    state = await auth.status(name, executable, self.home, self.agent_env())
                    self.authentication[name] = (time.monotonic(), executable, state)
                return name, {"available": True, "label": LABELS[name], "auth": state}
            return dict(await asyncio.gather(*(inspect(name) for name in AGENTS)))

    async def auth_status(self, params):
        agents = await self.agent_status(refresh=True)
        self.publish("agents.updated", {"agents": agents})
        return {"agents": agents}

    async def auth_login(self, params):
        name = params.get('agent')
        if name not in AGENTS:
            raise RpcFault(-32602, 'Choose Claude Code or Codex to sign in.')
        if any(lane.busy() for lane in self.lanes.values()):
            raise RpcFault(BUSY, 'Wait for the current question before signing in.')
        self.discovered = (0.0, {})
        executable = self.agents().get(name)
        if not executable:
            raise RpcFault(UNAVAILABLE, f'{LABELS[name]} is not installed. Enable it in Software first.')
        for lane in self.lanes.values():
            adapter = lane.adapters.pop(name, None)
            if adapter is not None:
                await adapter.close()
        self.authentication.pop(name, None)
        # The shell runs the agent's own browser authentication in the
        # background, its output discarded. Credentials never pass through the
        # assistant, QML or the JSON-RPC connection.
        return {"argv": [executable, *auth.LOGIN_ARGS[name]], "cwd": str(self.home)}

    def screenshot(self, value):
        if value in (None, ""):
            return None
        if not isinstance(value, str):
            raise RpcFault(-32602, "Invalid screenshot")
        try:
            real = Path(value).resolve(strict=True)
            root = self.shots.resolve(strict=True)
        except OSError:
            raise RpcFault(-32602, "The screenshot is no longer available.") from None
        if not policy.under(str(real), str(root)) or real == root or not real.is_file() \
                or real.suffix.lower() not in IMAGE_SUFFIXES or real.stat().st_size > MAX_SCREENSHOT:
            raise RpcFault(-32602, "The screenshot must be a PNG or JPEG taken by the assistant.")
        return real

    def attachments(self, value):
        """(text attachments for the note, images): what the person attached."""
        if value in (None, ""):
            return [], []
        if not isinstance(value, list) or len(value) > MAX_ATTACHMENTS:
            raise RpcFault(-32602, f"Attach at most {MAX_ATTACHMENTS} things to one question.")
        notes, images = [], []
        for item in value:
            if not isinstance(item, dict) or item.get("kind") not in ATTACHMENT_KINDS:
                raise RpcFault(-32602, "Invalid attachment")
            kind = item["kind"]
            label = " ".join(str(item.get("label") or "").split())[:200]
            if kind == "image":
                images.append(self.screenshot(item.get("path")))
                notes.append({"kind": "image", "label": label})
            elif kind == "file":
                path = item.get("path")
                if not isinstance(path, str) or not os.path.isabs(path):
                    raise RpcFault(-32602, "Invalid file")
                try:
                    if os.path.getsize(path) > MAX_FILE:
                        raise RpcFault(-32602, f"{os.path.basename(path)} is too large to attach (up to 256 KB).")
                    text = Path(path).read_bytes().decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    raise RpcFault(-32602, f"Only text files and images can be attached: "
                                           f"{os.path.basename(path)} is neither.") from None
                notes.append({"kind": "file", "label": label or os.path.basename(path), "text": text})
            elif kind == "window":
                notes.append({"kind": "window", "label": label})
            else:
                text = item.get("text")
                if not isinstance(text, str) or not text.strip():
                    continue
                notes.append({"kind": kind, "label": label, "text": text[:MAX_FILE]})
        return notes, images

    def _model(self, value):
        if value in (None, "", "default"):
            return None
        if not isinstance(value, str) or not MODEL.fullmatch(value):
            raise RpcFault(-32602, "Invalid model")
        return value

    async def turn_start(self, params):
        text = params.get("text")
        if not isinstance(text, str) or not text.strip():
            raise RpcFault(-32602, "Ask a question first.")
        text = text.strip()
        if len(text) > MAX_PROMPT:
            raise RpcFault(-32602, "That question is too long.")
        requested = params.get("agent") or "auto"
        if requested not in ("auto", *AGENTS):
            raise RpcFault(-32602, "Unknown agent")
        continued = params.get("conversation")
        if continued not in (None, "") and not isinstance(continued, str):
            raise RpcFault(-32602, "Invalid conversation")
        continued = continued or None
        if continued and self.history.get(continued) is None:
            raise RpcFault(NOT_FOUND, "That conversation is no longer in your history.")
        model = self._model(params.get("model"))
        context = turn_context(params.get("context"))
        shot = self.screenshot(params.get("screenshot"))
        notes, images = self.attachments(params.get("attachments"))
        if shot is not None:
            images.insert(0, shot)
        main, side = self.lanes["main"], self.lanes["side"]
        if not main.busy():
            lane = main
        elif side.busy() or (continued is not None and main.turn is not None
                             and main.turn.conversation == continued):
            if self.queue is not None:
                raise RpcFault(BUSY, "The assistant is still working on the previous question.")
            self.queue = {"id": "q-" + secrets.token_hex(6), "text": text, "agent": requested, "model": model,
                          "conversation": continued, "context": context, "notes": notes,
                          "images": [str(path) for path in images], "createdAt": now_ms(), "reason": "busy"}
            self.publish_queue()
            return {"queued": self.queue_summary()}
        else:
            lane = side
        turn = await self._begin(lane, text, requested, continued, model, context, notes, images)
        return {"turn": self.snapshot(turn)}

    async def _begin(self, lane, text, requested, continued, model, context, notes, images, routine=None,
                     queued=False):
        statuses = await self.agent_status()
        # Auth probing yields to other clients; a second start may have won.
        if lane.busy():
            raise RpcFault(BUSY, "The assistant is still working on the previous question.")
        # A conversation continues with the agent it started with.
        record = self.history.get(continued) if continued else None
        if continued and record is None:
            raise RpcFault(NOT_FOUND, "That conversation is no longer in your history.")
        agent = record["agent"] if record else (routine.get("agent") if routine and routine.get("agent")
                                                else self.resolve(requested, statuses))
        if statuses[agent]['available'] and statuses[agent]['auth'] != 'ready':
            raise RpcFault(-32004, f'Sign in to {LABELS[agent]} before asking the assistant. Your question has been kept.')
        if record is None:
            record = self.history.create(agent, routine={"id": routine["id"], "title": routine["title"]}
                                         if routine else None)
        settings = policy.read_json(self.settings_path)
        approval_policy = "ask" if settings.get("assistantApprovalPolicy") == "ask" else "always"
        turn = Turn("t-" + secrets.token_hex(8), agent, text, self.home,
                    self.memories.setdefault(record["id"], set()), self._turn_event,
                    screenshot=bool(images), approval_policy=approval_policy, conversation=record["id"],
                    lane=lane.name, look_only=lane.name == "side",
                    routine={"id": routine["id"], "title": routine["title"]} if routine else None, queued=queued)
        look_only = turn.look_only
        if not look_only:
            turn.snapshots.begin()
        plugins = policy.plugin_manifests(self.home)
        status = policy.read_json(self.status_path)
        lane.turn = turn
        lane.active = record
        self.quiet_since = time.monotonic()
        self.history.begin(record, turn)
        lane.task = asyncio.create_task(self._run(lane, turn, record, text, images, model, context, notes,
                                                  plugins, status, requested))
        if lane.name == "main":
            self.save()
        self._turn_event("updated", turn)
        self.publish_history()
        return turn

    async def _run(self, lane, turn, record, text, images, model, context, notes, plugins, status, requested):
        try:
            executable = self.agents().get(turn.agent)
            if not executable:
                message = (f"{LABELS[turn.agent]} is not installed." if requested != "auto"
                           else "Neither Claude Code nor Codex is installed.")
                turn.finish("failed", error=message, kind="missing")
                return
            pictures = [(path.read_bytes(), media_type(path)) if turn.agent == "claude" else str(path)
                        for path in images]
            adapter = self.adapter(lane, turn.agent, executable)
            await adapter.use(record["session"])
            question = prompt.turn_text(text, context, bool(images), notes, look_only=lane.name == "side",
                                        routine=(turn.routine or {}).get("title"), queued=turn.queued)
            outcome = await adapter.run(turn, question, pictures, model)
            turn.finish(outcome.get("status", "failed"), outcome.get("text"), outcome.get("error", ""),
                        outcome.get("kind", ""))
            if turn.error_kind == 'auth':
                self.authentication[turn.agent] = (time.monotonic(), executable, 'required')
                self.publish('agents.updated', {'agents': await self.agent_status()})
        except FileNotFoundError:
            turn.finish("failed", error=f"{LABELS[turn.agent]} is not installed.", kind="missing")
        except asyncio.CancelledError:
            if self.closing:
                turn.finish("failed", error=RESTARTED, kind="crashed")
            else:
                turn.finish("stopped")
            raise
        except Exception as error:
            LOG.exception("turn failed")
            turn.finish("failed", error=str(error) or "The assistant could not finish.", kind="crashed")
        finally:
            for path in images:
                with contextlib.suppress(OSError):
                    path.unlink()
            if not turn.finished:
                turn.finish("failed", error="The assistant could not finish.", kind="crashed")
            self._settle(lane, turn, record, plugins, status)

    def _settle(self, lane, turn, record, plugins, status):
        """What a finished turn left behind, and what runs next."""
        self.quiet_since = time.monotonic()
        recorded = []
        if not turn.look_only:
            turn.snapshots.finish()
            recorded = self.changes.from_snapshots(turn, turn.snapshots)
            turn.plugins = policy.new_plugins(plugins, policy.plugin_manifests(self.home))
            turn.staged = policy.staged_transaction(status, policy.read_json(self.status_path))
            if turn.staged:
                recorded.append(self.changes.add(turn, "system", "system:" + turn.staged, transaction=turn.staged))
        if recorded or any(entry["turn"] == turn.id for entry in self.changes.entries):
            self.changes.save()
        if turn.routine:
            attention, rest = routines.split_attention(turn.text)
            turn.text = rest
            turn.attention = True if turn.status == "failed" else bool(attention)
        self.history.finish(record, turn)
        if lane.name == "main":
            self.save()
        self._turn_event("updated", turn)
        self.publish_history()
        if recorded:
            self.publish("changes.updated", {"count": len(self.changes.entries)})
        if lane.name == "side" and turn.needs_change and turn.status == "completed" and self.queue is None \
                and self.history.get(record["id"]) is not None:
            self.queue = {"id": "q-" + secrets.token_hex(6), "text": turn.prompt, "agent": record["agent"],
                          "model": None, "conversation": record["id"], "context": {}, "notes": [], "images": [],
                          "createdAt": now_ms(), "reason": "change"}
            self.publish_queue()
        if turn.routine:
            self._routine_finished(turn, record)
        if not self.closing:
            self._spawn(self._next())

    async def _next(self):
        """Starts what waits for the main lane: the queued question first, then routines."""
        await asyncio.sleep(0)
        main = self.lanes["main"]
        if main.busy() or self.closing:
            return
        if self.queue is not None:
            if self.lanes["side"].busy() and self.lanes["side"].turn.conversation == self.queue["conversation"]:
                return
            item, self.queue = self.queue, None
            self.publish_queue()
            continued = item["conversation"] if self.history.get(item["conversation"]) else None
            try:
                await self._begin(main, item["text"], item["agent"], continued, item["model"], item["context"],
                                  item["notes"], [Path(path) for path in item["images"]], queued=True)
            except RpcFault as fault:
                for path in item["images"]:
                    with contextlib.suppress(OSError):
                        os.unlink(path)
                self.publish("notice", {"text": fault.message})
            return
        while self.waiting_routines and not main.busy():
            routine = self.routines.get(self.waiting_routines.pop(0))
            if routine is not None and await self._start_routine(routine):
                return

    async def turn_stop(self, params):
        lane = self.lanes.get(params.get("lane") or "main")
        if lane is None:
            raise RpcFault(-32602, "Unknown lane")
        turn, task = lane.turn, lane.task
        if task is None or task.done():
            return {"stopped": False}
        turn.stopping = True
        turn.deny_all()
        adapter = lane.adapters.get(turn.agent)
        if adapter is not None:
            await adapter.interrupt()
        try:
            await asyncio.wait_for(asyncio.shield(task), STOP_WAIT)
        except asyncio.TimeoutError:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await task
        return {"stopped": True}

    async def approval_respond(self, params):
        decision = params.get("decision")
        if decision not in ("allow", "always", "deny"):
            raise RpcFault(-32602, "Invalid decision")
        for lane in self.lanes.values():
            if lane.turn is not None and lane.turn.respond(params.get("id"), decision):
                return {"ok": True}
        raise RpcFault(NOT_FOUND, "That approval is no longer pending.")

    # ---- the queue ------------------------------------------------------------

    async def queue_remove(self, params):
        item, self.queue = self.queue, None
        if item is not None:
            for path in item["images"]:
                with contextlib.suppress(OSError):
                    os.unlink(path)
            self.publish_queue()
        return {"ok": item is not None}

    async def queue_run(self, params):
        """Stops the main question, so the waiting one starts now."""
        if self.queue is None:
            raise RpcFault(NOT_FOUND, "Nothing is waiting.")
        if self.lanes["main"].busy():
            await self.turn_stop({"lane": "main"})
        else:
            await self._next()
        return {"ok": True}

    # ---- changes ---------------------------------------------------------------

    async def turn_undo(self, params):
        """Undoes everything one answer changed that can still be undone."""
        identifier = params.get("id")
        rows = [row for row in self.changes.summaries(self._exists, turn=identifier) if row["undoable"]]
        if not rows:
            raise RpcFault(NOT_FOUND, "There is nothing to undo.")
        restored, skipped = [], []
        for row in rows:
            entry = self.changes.get(row["id"])
            reason = await self._undo_entry(entry)
            shown = row.get("path") or "~/.config/cybexos/shell.json"
            (skipped if reason else restored).append(shown)
        self.publish_changes()
        return {"restored": sorted(set(restored)), "skipped": sorted(set(skipped))}

    async def change_list(self, params):
        if self.changes.enforce():
            self.changes.save()
        return {"changes": self.changes.summaries(self._exists)}

    async def change_undo(self, params):
        ids = params.get("ids") if isinstance(params.get("ids"), list) else [params.get("id")]
        if not ids or not all(isinstance(identifier, str) for identifier in ids):
            raise RpcFault(-32602, "Name the change to undo.")
        status = {row["id"]: row for row in self.changes.summaries(self._exists)}
        restored, skipped = [], []
        # Newest first, so one change never waits for another undone with it.
        for identifier in sorted(ids, key=lambda value: (status.get(value) or {}).get("at", 0), reverse=True):
            row = status.get(identifier)
            entry = self.changes.get(identifier)
            if row is None or entry is None:
                skipped.append({"id": identifier, "reason": "That change is no longer in the log."})
                continue
            if row["status"] == "blocked":
                skipped.append({"id": identifier, "reason": "A later change to the same thing comes first."})
                continue
            if row["status"] != "applied":
                skipped.append({"id": identifier, "reason": "It was changed since, so it was left as it is."
                                if row["status"] == "changed" else "It cannot be undone here."})
                continue
            reason = await self._undo_entry(entry)
            if reason:
                skipped.append({"id": identifier, "reason": reason})
            else:
                restored.append(identifier)
            status = {row["id"]: row for row in self.changes.summaries(self._exists)}
        self.publish_changes()
        return {"restored": restored, "skipped": skipped}

    async def _undo_entry(self, entry):
        """"" once undone, else why it could not be."""
        kind = entry["kind"]
        if kind in ("setting", "file", "plugin"):
            reason = self.changes.undo_local(entry)
        elif kind == "app":
            app = entry.get("app") or {}
            action = "remove" if entry.get("op") == "installed" else "install"
            try:
                await self._flathub(action, app.get("id", ""), app.get("name") or app.get("id", ""))
                reason = ""
            except DesktopError as error:
                reason = str(error)
        elif kind == "routine":
            data = (entry.get("routine") or {}).get("data")
            if entry.get("op") == "created":
                reason = "" if self.routines.delete(entry["routine"]["id"]) else "That routine is already gone."
            elif isinstance(data, dict):
                self.routines.items.append(data)
                self.routines.save()
                reason = ""
            else:
                reason = "That routine can no longer be restored."
            self.publish_routines()
        else:
            reason = "Software Update undoes system changes."
        if not reason:
            self.changes.mark_undone(entry)
        return reason

    # ---- the history ---------------------------------------------------------

    def _conversation(self, params):
        identifier = params.get("id")
        record = self.history.get(identifier) if isinstance(identifier, str) else None
        if record is None:
            raise RpcFault(NOT_FOUND, "That conversation is no longer in your history.")
        return record

    async def conversation_list(self, params):
        query = params.get("query") or ""
        if not isinstance(query, str) or len(query) > 200:
            raise RpcFault(-32602, "Invalid query")
        running = [lane.turn.conversation for lane in self.lanes.values() if lane.busy()]
        if self.history.enforce(keep=running[0] if len(running) == 1 else None) | self.changes.enforce():
            self.save()
            self.changes.save()
            self.publish_history()
        return {"conversations": self.summaries(query.strip())}

    async def conversation_open(self, params):
        """The whole conversation, the running answer included as it stands."""
        record = self._conversation(params)
        turns = list(record["turns"])
        live = None
        for lane in self.lanes.values():
            if lane.turn is not None and lane.turn.conversation == record["id"]:
                if turns and turns[-1]["id"] == lane.turn.id:
                    turns[-1] = self.history.entry(lane.turn)
                live = self.snapshot(lane.turn)
        return {"conversation": dict(self.history.summary(record, live), turns=turns,
                                     resumable=bool(record["session"]))}

    async def _stop_in(self, identifier=None):
        """Stops a running question when it belongs to `identifier` (any
        conversation when None) before that conversation is removed."""
        for lane in self.lanes.values():
            if lane.busy() and (identifier is None or lane.turn.conversation == identifier):
                await self.turn_stop({"lane": lane.name})

    async def conversation_delete(self, params):
        record = self._conversation(params)
        await self._stop_in(record["id"])
        if self.history.delete(record["id"]) is None:
            raise RpcFault(NOT_FOUND, "That conversation is no longer in your history.")
        self.memories.pop(record["id"], None)
        self.changes.forget_conversation(record["id"])
        if self.queue is not None and self.queue["conversation"] == record["id"]:
            await self.queue_remove({})
        self.save()
        self.publish_history()
        for lane in self.lanes.values():
            if lane.turn is not None and lane.turn.conversation == record["id"]:
                self._turn_event("updated", lane.turn)
        return {"ok": True}

    async def conversation_restore(self, params):
        identifier = params.get("id")
        record = self.history.restore(identifier) if isinstance(identifier, str) else None
        if record is None:
            raise RpcFault(NOT_FOUND, "That conversation can no longer be restored.")
        self.save()
        self.publish_history()
        for lane in self.lanes.values():
            if lane.turn is not None and lane.turn.conversation == record["id"]:
                self._turn_event("updated", lane.turn)
        return {"conversation": self.history.summary(record)}

    async def conversation_clear(self, params):
        """Every conversation, the change log and the last answer kept for
        the box. The agents' own session files are left alone."""
        await self.queue_remove({})
        await self._stop_in()
        self.history.clear()
        self.changes.clear()
        self.memories = {}
        for lane in self.lanes.values():
            lane.active = None
            lane.turn = None
        await self._close_adapters()
        self.save()
        self.publish("turn.updated", {"turn": None, "lane": "main"})
        self.publish("turn.updated", {"turn": None, "lane": "side"})
        self.publish_history()
        self.publish("changes.updated", {"count": 0})
        return {"ok": True}

    async def conversation_handoff(self, params):
        main = self.lanes["main"]
        identifier = params.get("id") or (main.turn.conversation if main.turn is not None else None)
        record = self.history.get(identifier) if isinstance(identifier, str) else None
        for lane in self.lanes.values():
            if lane.busy() and (record is None or lane.turn.conversation == record["id"]):
                raise RpcFault(BUSY, "Wait until the assistant has answered, then continue in a terminal.")
        if record is None or not record["session"]:
            raise RpcFault(UNAVAILABLE, "There is no conversation to continue.")
        agent, session = record["agent"], record["session"]
        executable = self.agents().get(agent) or agent
        argv = [executable, "--resume", session] if agent == "claude" else [executable, "resume", session]
        # The terminal continues the session from disk; a later question
        # here resumes it again instead of forking the history.
        for lane in self.lanes.values():
            adapter = lane.adapters.get(agent)
            if adapter is not None and adapter.conversation_id == session:
                lane.adapters.pop(agent)
                await adapter.close()
        return {"argv": argv, "cwd": str(self.home)}

    async def speech_say(self, params):
        text = params.get("text")
        if not isinstance(text, str) or len(text) > 64 * 1024:
            raise RpcFault(-32602, "Invalid text")
        language = params.get("language")
        if language is not None and (not isinstance(language, str) or not LANGUAGE.fullmatch(language)):
            language = None
        return await self.speaker.say(text, language)

    async def speech_stop(self, params):
        await self.speaker.stop()
        return {"ok": True}

    # ---- routines --------------------------------------------------------------

    async def routine_list(self, params):
        return {"routines": self.routines.summaries()}

    async def routine_create(self, params):
        routine, error = self.routines.create(params.get("question"), params.get("schedule"),
                                              params.get("title"), params.get("notify"), params.get("agent"),
                                              version=prompt.release(self.release_path))
        if error:
            raise RpcFault(-32602, error)
        if params.get("purpose") in prompt.PURPOSE_NOTES:
            routine["purpose"] = params["purpose"]
            self.routines.save()
        self.publish_routines()
        return {"routine": routine}

    async def routine_update(self, params):
        changes = {key: params[key] for key in ("question", "title", "notify", "enabled", "schedule") if key in params}
        routine, error = self.routines.update(params.get("id"), changes)
        if error:
            raise RpcFault(-32602 if routine is None and "exists" not in error else NOT_FOUND, error)
        self.publish_routines()
        return {"routine": routine}

    async def routine_delete(self, params):
        routine = self.routines.delete(params.get("id"))
        if routine is None:
            raise RpcFault(NOT_FOUND, "That routine no longer exists.")
        if routine["id"] in self.waiting_routines:
            self.waiting_routines.remove(routine["id"])
        self.publish_routines()
        return {"ok": True}

    async def routine_run(self, params):
        routine = self.routines.get(params.get("id"))
        if routine is None:
            raise RpcFault(NOT_FOUND, "That routine no longer exists.")
        if self.lanes["main"].busy() or self.queue is not None:
            if routine["id"] not in self.waiting_routines:
                self.waiting_routines.append(routine["id"])
            return {"started": False, "waiting": True}
        started = await self._start_routine(routine, raising=True)
        return {"started": started, "waiting": False}

    async def _start_routine(self, routine, raising=False):
        context = {"purpose": routine["purpose"]} if routine.get("purpose") in prompt.PURPOSE_NOTES else {}
        try:
            await self._begin(self.lanes["main"], routine["question"], routine.get("agent") or "auto", None, None,
                              context, [], [], routine=routine)
            return True
        except RpcFault as fault:
            self.routines.ran(routine, prompt.release(self.release_path),
                              {"status": "failed", "error": fault.message, "attention": True, "at": now_ms(),
                               "conversation": None, "summary": fault.message})
            self.publish_routines()
            self.publish("routine.finished", {"routine": {"id": routine["id"], "title": routine["title"]},
                                              "conversation": None, "attention": True, "notify": True,
                                              "summary": fault.message})
            if raising:
                raise
            return False

    def _routine_finished(self, turn, record):
        routine = self.routines.get(turn.routine["id"])
        summary = history_module.collapse(turn.error if turn.status == "failed" else turn.text, 200)
        notify = bool(turn.attention) or bool(routine and routine.get("notify") == "always")
        if routine is not None:
            self.routines.ran(routine, prompt.release(self.release_path),
                              {"status": turn.status, "attention": bool(turn.attention), "at": now_ms(),
                               "conversation": record["id"], "summary": summary})
            self.publish_routines()
        self.publish("routine.finished", {"routine": turn.routine, "conversation": record["id"],
                                          "attention": bool(turn.attention), "notify": notify, "summary": summary})

    async def _schedule(self):
        await asyncio.sleep(5)
        while not self.closing:
            try:
                version = prompt.release(self.release_path)
                before = json.dumps(self.routines.items, sort_keys=True)
                for routine in self.routines.due(now_ms(), version):
                    if routine["id"] not in self.waiting_routines:
                        self.waiting_routines.append(routine["id"])
                if json.dumps(self.routines.items, sort_keys=True) != before:
                    self.routines.save()
                if self.waiting_routines and not self.lanes["main"].busy() and self.queue is None:
                    await self._next()
            except Exception:
                LOG.exception("routine scheduling failed")
            await asyncio.sleep(ROUTINE_TICK)

    # ---- renewal after an update -------------------------------------------------

    def outdated(self):
        """An update replaced this service's unit since it started."""
        current = unit_identity(self.unit_path)
        return self.unit is not None and current is not None and current != self.unit

    def renewable(self):
        """A restart now loses nothing the person is using: no question runs
        or waits, nothing is spoken, the last answer has had time to be read
        (the main lane's is kept across the restart, see save), and
        conversations are kept on disk rather than only for this session."""
        return (not any(lane.busy() for lane in self.lanes.values())
                and self.queue is None and not self.waiting_routines and not self.desktop_pending
                and not self.auth_lock.locked() and not self.speaker.speaking
                and history_module.retention(policy.read_json(self.settings_path)) != "session"
                and time.monotonic() - self.quiet_since >= RENEW_QUIET)

    async def _renew(self):
        while not self.closing:
            await asyncio.sleep(RENEW_TICK)
            try:
                if self.outdated() and self.renewable():
                    LOG.info("the assistant service was updated; restarting into it")
                    self.renewing = True
                    if self.stopping is not None:
                        self.stopping.set()
                    return
            except Exception:
                LOG.exception("renewal check failed")

    # ---- desktop tools -----------------------------------------------------------

    async def desktop_call(self, params):
        """A desktop tool the agent called through mcp.py: {isError, text}."""
        name = desktop.tool_name(params.get("tool"))
        arguments = params.get("arguments") if isinstance(params.get("arguments"), dict) else {}
        lane = self.lanes.get(params.get("lane") or "main")
        if lane is None or not lane.busy() or lane.turn is None:
            return {"isError": True, "text": "No question is in progress, so the desktop tools are not available."}
        turn = lane.turn
        problem = desktop.validate(name, arguments)
        if problem:
            return {"isError": True, "text": problem}
        spec = desktop.TOOLS[name]
        decision = await self._desktop_decision(name, spec, arguments)
        answer, note = await turn.authorize(decision)
        if answer not in ("allow", "always"):
            return {"isError": True, "text": note or "The person declined this."}
        turn.add_step(steps.entry(spec["label"], desktop.detail(name, arguments), tool=True))
        turn.set_step(desktop.PRESENT.get(name, "Working"))
        try:
            result = await self._desktop(name, arguments, turn)
        except DesktopError as error:
            return {"isError": True, "text": str(error)}
        except Exception as error:
            LOG.exception("desktop tool %s failed", name)
            return {"isError": True, "text": str(error) or "The tool failed."}
        text = result if isinstance(result, str) else json.dumps(result, ensure_ascii=False)
        return {"isError": False, "text": text[:60000]}

    async def _desktop_decision(self, name, spec, arguments):
        kind = spec["kind"]
        if kind == desktop.LOOK:
            return policy.allow()
        if kind == desktop.INSTALL:
            app = arguments.get("id", "")
            label = arguments.get("name") or app
            verb = "Install" if name == "flatpak_install" else "Remove"
            card = {"kind": "other", "title": f"{verb} {label}?", "detail": "",
                    "facts": [{"label": "App", "value": f"{label} · {app}" if label != app else app},
                              {"label": "From", "value": "Flathub"},
                              {"label": "For", "value": "Your account only"}],
                    "glyph": "download" if verb == "Install" else "delete"}
            return policy.Decision("ask", card=card, key=("flatpak", name, app), changes=True)
        if spec.get("always_ask"):
            window = {}
            with contextlib.suppress(DesktopError, asyncio.TimeoutError):
                window = await self._ask_shell("window_info", {"address": arguments.get("address", "")}, 5)
            title = window.get("title") if isinstance(window, dict) else ""
            card = {"kind": "other", "title": "Close this window?",
                    "detail": "The app may have unsaved work.",
                    "facts": [{"label": "Window", "value": title or arguments.get("address", "")}]
                    + ([{"label": "App", "value": window["app"]}] if isinstance(window, dict) and window.get("app") else []),
                    "glyph": "close"}
            return policy.Decision("ask", card=card, always=True, changes=True)
        return policy.Decision("allow", changes=True)

    async def _desktop(self, name, arguments, turn):
        spec = desktop.TOOLS[name]
        if spec["where"] == "shell":
            if name == "wallpaper_set" and arguments.get("wallhaven"):
                arguments = dict(arguments, record=await self._wallpaper_record(arguments["wallhaven"]))
            timeout = SHELL_SLOW_TIMEOUT if name == "wallpaper_set" else SHELL_TIMEOUT
            return await self._ask_shell(name, arguments, timeout)
        if name == "wallpaper_search":
            return await asyncio.to_thread(self._wallhaven_search, arguments["query"])
        if name == "software_search":
            found = await self._cybex(["software", "flathub", "search", arguments["query"]], 60)
            rows = found.get("results") if isinstance(found, dict) else []
            return {"results": [{key: row.get(key) for key in ("id", "name", "summary", "developer")
                                 if key in row} for row in (rows or [])[:12] if isinstance(row, dict)]}
        if name in ("flatpak_install", "flatpak_remove"):
            app = arguments["id"]
            label = arguments.get("name") or app
            action = "install" if name == "flatpak_install" else "remove"
            await self._flathub(action, app, label)
            entry = self.changes.add(turn, "app", "app:" + app, app={"id": app, "name": label},
                                     op="installed" if action == "install" else "removed")
            self.changes.save()
            self.publish_changes()
            return {"done": True, "change": entry["id"]}
        if name == "doctor_run":
            return await self._cybex(["doctor", "--json"], 180)
        if name == "routine_list":
            return {"routines": self.routines.summaries()}
        if name == "routine_create":
            routine, error = self.routines.create(arguments["question"], arguments["schedule"],
                                                  arguments.get("title"), arguments.get("notify"), turn.agent,
                                                  version=prompt.release(self.release_path))
            if error:
                raise DesktopError(error)
            turn.routines.append({"id": routine["id"], "title": routine["title"],
                                  "schedule": routine["schedule"], "notify": routine["notify"]})
            self.changes.add(turn, "routine", "routine:" + routine["id"], op="created",
                             routine={"id": routine["id"], "title": routine["title"]})
            self.changes.save()
            self.publish_routines()
            self.publish_changes()
            return {"routine": routine}
        if name == "routine_delete":
            routine = self.routines.delete(arguments["id"])
            if routine is None:
                raise DesktopError("That routine no longer exists.")
            self.changes.add(turn, "routine", "routine:" + routine["id"], op="deleted",
                             routine={"id": routine["id"], "title": routine["title"], "data": routine})
            self.changes.save()
            self.publish_routines()
            self.publish_changes()
            return {"deleted": routine["id"]}
        raise DesktopError(f"{name} is not available.")

    async def _ask_shell(self, tool, arguments, timeout):
        shells = [client for client in self.clients if client.kind == "quickshell" and not client.closed]
        if not shells:
            raise DesktopError("The desktop shell is not running, so this cannot be done now.")
        identifier = "d-" + secrets.token_hex(8)
        future = asyncio.get_running_loop().create_future()
        self.desktop_pending[identifier] = future
        frame = encode(notification("desktop.request", {"id": identifier, "tool": tool, "arguments": arguments}))
        for client in shells:
            client.send(frame)
        try:
            answer = await asyncio.wait_for(future, timeout)
        except asyncio.TimeoutError:
            raise DesktopError("The desktop did not answer in time.") from None
        finally:
            self.desktop_pending.pop(identifier, None)
        if not answer.get("ok"):
            raise DesktopError(str(answer.get("error") or "The desktop could not do that."))
        return answer.get("result")

    async def desktop_respond(self, params):
        future = self.desktop_pending.get(params.get("id"))
        if future is None or future.done():
            return {"ok": False}
        future.set_result({"ok": bool(params.get("ok")), "result": params.get("result"),
                           "error": params.get("error")})
        return {"ok": True}

    async def _cybex(self, args, timeout):
        """`cybex …` with JSON output, run as the person."""
        executable = shutil.which("cybex", path=self.agent_env()["PATH"]) or "cybex"
        try:
            process = await asyncio.create_subprocess_exec(
                executable, *args, cwd=str(self.home), env=self.agent_env(), stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        except OSError as error:
            raise DesktopError(f"cybex could not run: {error}") from None
        try:
            output, errors = await asyncio.wait_for(process.communicate(), timeout)
        except asyncio.TimeoutError:
            with contextlib.suppress(ProcessLookupError):
                process.kill()
            raise DesktopError("cybex took too long.") from None
        text = output.decode("utf-8", "replace")
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            value = None
        if process.returncode != 0 and value is None:
            raise DesktopError((errors.decode("utf-8", "replace").strip() or text.strip()
                                or f"cybex failed with status {process.returncode}.")[:800])
        return value if value is not None else text[:30000]

    async def _flathub(self, action, app, label):
        if not re.fullmatch(r"[A-Za-z0-9_.-]{3,255}", app or ""):
            raise DesktopError("That is not a Flathub app id.")
        started = await self._cybex(["software", "flathub", action, "--names", json.dumps({app: label}), app], 60)
        task = started.get("task") if isinstance(started, dict) else None
        if not task:
            raise DesktopError(f"The {action} could not start.")
        deadline = time.monotonic() + FLATHUB_TIMEOUT
        while time.monotonic() < deadline:
            await asyncio.sleep(2)
            status = await self._cybex(["software", "flathub", "status"], 30)
            current = status.get("task") if isinstance(status, dict) else None
            if isinstance(current, dict) and current.get("id") == task:
                if current.get("state") == "done":
                    return
                if current.get("state") == "failed":
                    raise DesktopError(current.get("error") or f"The {action} failed.")
        raise DesktopError(f"The {action} is still running; Software shows how it ends.")

    def _wallhaven_get(self, path, query=None):
        url = f"{WALLHAVEN}/{path}" + ("?" + urllib.parse.urlencode(query) if query else "")
        request = urllib.request.Request(url, headers={"User-Agent": "Cybex OS Assistant"})
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.loads(response.read(2 * 1024 * 1024).decode("utf-8"))
        except (OSError, ValueError) as error:
            raise DesktopError(f"Wallhaven could not be reached: {error}") from None

    def _wallhaven_search(self, query):
        data = self._wallhaven_get("search", {"q": query, "categories": "100", "purity": "100",
                                              "sorting": "relevance", "atleast": "1920x1080"})
        rows = data.get("data") if isinstance(data, dict) else []
        results = []
        for row in (rows or [])[:10]:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str):
                continue
            self.wallpapers[row["id"]] = row
            results.append({"id": row["id"], "resolution": row.get("resolution"), "colors": row.get("colors"),
                            "page": row.get("url"), "thumbnail": (row.get("thumbs") or {}).get("small")})
        return {"results": results}

    async def _wallpaper_record(self, identifier):
        if not re.fullmatch(r"[a-z0-9]{4,12}", identifier or ""):
            raise DesktopError("That is not a Wallhaven id.")
        record = self.wallpapers.get(identifier)
        if record is None:
            data = await asyncio.to_thread(self._wallhaven_get, f"w/{identifier}")
            record = data.get("data") if isinstance(data, dict) else None
            if not isinstance(record, dict):
                raise DesktopError("Wallhaven has no such wallpaper.")
            if record.get("purity") != "sfw":
                raise DesktopError("Only safe-for-work wallpapers can be set.")
        return record

    # ---- persistence -------------------------------------------------------

    def _load(self):
        self.history.load(("failed", RESTARTED, "crashed"))
        self.changes.load()
        self.routines.load()
        data = policy.read_json(self.state_path)
        stored = data.get("turn")
        if isinstance(stored, dict) and stored.get("agent") in AGENTS and isinstance(stored.get("id"), str):
            conversation = stored.get("conversation") if self.history.get(stored.get("conversation")) else None
            turn = Turn(stored["id"], stored["agent"], str(stored.get("prompt") or ""), self.home,
                        self.memories.setdefault(conversation, set()) if conversation else set(),
                        self._turn_event, screenshot=bool(stored.get("screenshot")), conversation=conversation)
            turn.text = str(stored.get("text") or "")
            turn.started_at = int(stored.get("startedAt") or 0)
            if stored.get("status") in FINAL:
                turn.status = stored["status"]
                turn.error = str(stored.get("error") or "")
                turn.error_kind = str(stored.get("errorKind") or "")
                turn.finished_at = int(stored.get("finishedAt") or 0)
            else:
                turn.status, turn.error, turn.error_kind, turn.finished_at = "failed", RESTARTED, "crashed", now_ms()
            turn.step = ""
            plugins = stored.get("plugins")
            turn.plugins = [entry for entry in plugins if isinstance(entry, dict)
                            and isinstance(entry.get("id"), str) and policy.PLUGIN_ID.fullmatch(entry["id"])] \
                if isinstance(plugins, list) else []
            turn.staged = stored.get("staged") if isinstance(stored.get("staged"), str) else ""
            stored_steps = stored.get("steps")
            turn.steps = [step for step in stored_steps if isinstance(step, dict)
                          and isinstance(step.get("label"), str)][:steps.MAX_STEPS] \
                if isinstance(stored_steps, list) else []
            self.turn = turn

    def save(self):
        """The last answer, for the box after a restart. It is kept only while
        its conversation is, and only when conversations are saved."""
        turn = self.snapshot(self.lanes["main"].turn)
        if turn is not None:
            turn["approvals"] = []
            turn["changes"] = []
            if self.history.mode == "session" or self.history.get(turn["conversation"]) is None:
                turn = None
        document = {"version": 2, "turn": turn}
        try:
            self.state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            handle, temporary = tempfile.mkstemp(prefix=".state-", dir=self.state_path.parent)
            with os.fdopen(handle, "wb") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(encode(document))
            os.replace(temporary, self.state_path)
        except OSError as error:
            LOG.warning("could not save assistant state: %s", error)

    # ---- socket ------------------------------------------------------------

    async def _connection(self, reader, writer):
        client = Client(writer)
        self.clients.add(client)
        try:
            async for line in iter_lines(reader, MAX_LINE):
                message = parse_json(line)
                if message is None:
                    client.send(encode(error_frame(None, -32700, "Parse error")))
                    continue
                self._spawn(self._request(client, message))
        except (ConnectionError, OSError):
            pass
        finally:
            self.clients.discard(client)
            client.close()

    async def _request(self, client, message):
        identifier = message.get("id")
        method = message.get("method")
        params = message.get("params") if message.get("params") is not None else {}
        try:
            if not isinstance(method, str) or not isinstance(params, dict):
                raise RpcFault(-32600, "Invalid request")
            handler = self.methods.get(method)
            if handler is None:
                raise RpcFault(-32601, f"Unknown method {method}")
            if method == "hello" and isinstance(params.get("client"), str):
                client.kind = params["client"][:40]
            result = await handler(params)
        except RpcFault as fault:
            if identifier is not None:
                client.send(encode(error_frame(identifier, fault.code, fault.message)))
        except Exception:
            LOG.exception("%s failed", method)
            if identifier is not None:
                client.send(encode(error_frame(identifier, -32603, "Internal error")))
        else:
            if identifier is not None:
                client.send(encode(result_frame(identifier, result)))

    def _prepare(self):
        for directory in (self.socket_path.parent, self.shots):
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            with contextlib.suppress(OSError):
                os.chmod(directory, 0o700)
        # A screenshot belongs to one question; none survives the service.
        for leftover in self.shots.iterdir():
            if leftover.is_file() or leftover.is_symlink():
                with contextlib.suppress(OSError):
                    leftover.unlink()
        if self.socket_path.exists() or self.socket_path.is_symlink():
            probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                probe.settimeout(1)
                probe.connect(str(self.socket_path))
            except OSError:
                self.socket_path.unlink()
            else:
                raise SystemExit(f"cybexos-assistant: already running at {self.socket_path}")
            finally:
                probe.close()

    async def start(self):
        self._prepare()
        self.listener = await asyncio.start_unix_server(self._connection, path=str(self.socket_path))
        os.chmod(self.socket_path, 0o600)
        self.scheduler = asyncio.create_task(self._schedule())

    async def shutdown(self):
        self.closing = True
        if self.scheduler is not None:
            self.scheduler.cancel()
        if self.listener is not None:
            self.listener.close()
        for client in list(self.clients):
            client.close()
        await self.speaker.stop()
        for lane in self.lanes.values():
            if lane.busy():
                lane.task.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await lane.task
        await self._close_adapters()
        self.save()
        with contextlib.suppress(OSError):
            self.socket_path.unlink()
        for task in list(self.tasks):
            task.cancel()

    async def serve(self):
        """Runs until stopped; RENEW_EXIT asks systemd to start the updated unit."""
        await self.start()
        self.stopping = asyncio.Event()
        loop = asyncio.get_running_loop()
        for number in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(number, self.stopping.set)
        renewal = self._spawn(self._renew()) if self.unit is not None else None
        LOG.info("listening on %s", self.socket_path)
        await self.stopping.wait()
        if renewal is not None:
            renewal.cancel()
        await self.shutdown()
        return RENEW_EXIT if self.renewing else 0

