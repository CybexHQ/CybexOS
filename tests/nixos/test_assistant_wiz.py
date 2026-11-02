"""Wiz's newer service features against the same fake agents as test_assistant.py:
the step list, the change log and its Undo, a question asked alongside another
and the queue, attachments, the desktop tools (desktop.call, the shell's
desktop.request and the MCP server) and routines.
"""

import asyncio
import contextlib
import datetime
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "desktop" / "assistant"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from cybexos_assistant import changes, desktop, mcp, policy, prompt, routines, steps  # noqa: E402
from cybexos_assistant.turn import Turn  # noqa: E402
from test_assistant import Client, Harness, ServiceTest  # noqa: E402


class FakeShell:
    """A quickshell client that answers desktop.request like the shell does."""

    def __init__(self, answers):
        self.answers = answers
        self.requests = []
        self.client = None
        self.task = None

    async def open(self, path):
        self.client = await Client().open(path)
        await self.client.result("hello", {"client": "quickshell", "protocol": 1})
        self.task = asyncio.create_task(self._serve())
        return self

    async def _serve(self):
        seen = 0
        while True:
            while seen < len(self.client.notifications):
                message = self.client.notifications[seen]
                seen += 1
                if message["method"] != "desktop.request":
                    continue
                params = message["params"]
                self.requests.append((params["tool"], params["arguments"]))
                answer = self.answers.get(params["tool"], {"ok": True, "result": {"done": True}})
                await self.client.call("desktop.respond", dict(answer, id=params["id"]))
            await asyncio.sleep(0.01)

    async def close(self):
        self.task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await self.task
        await self.client.close()


class FakeTurn:
    def __init__(self, identifier, prompt_text="Make the bar transparent"):
        self.id = identifier
        self.conversation = "c-" + "0" * 16
        self.prompt = prompt_text


class StepsTest(unittest.TestCase):
    def test_records_read_plainly(self):
        self.assertEqual(steps.claude_record("Read", {"file_path": "/h/.config/cybexos/shell.json"}),
                         {"label": "Read a file", "detail": "shell.json", "tool": False})
        self.assertEqual(steps.claude_record("mcp__cybexos__settings_set", {"key": "barOpacity", "value": 0.8}),
                         {"label": "Changed a preference", "detail": "barOpacity", "tool": True})
        self.assertIsNone(steps.claude_record("TodoWrite", {}))
        self.assertEqual(steps.codex_record({"type": "commandExecution", "command": "ls ~"})["label"], "Ran a command")
        self.assertEqual(steps.claude_tool("mcp__cybexos__wallpaper_set", {}), "Setting the wallpaper")

    def test_turn_skips_repeats_and_stops_at_the_limit(self):
        turn = Turn("t-1", "claude", "q", "/tmp", set(), lambda *args: None)
        for _ in range(3):
            turn.add_step(steps.entry("Read a file", "a"))
        self.assertEqual(len(turn.steps), 1)
        for index in range(100):
            turn.add_step(steps.entry("Read a file", str(index)))
        self.assertEqual(len(turn.steps), steps.MAX_STEPS)


class DesktopToolsTest(unittest.TestCase):
    def test_every_tool_is_described_and_named_for_mcp(self):
        listing = desktop.listing()
        self.assertEqual({tool["name"] for tool in listing}, set(desktop.TOOLS))
        for tool in listing:
            self.assertRegex(tool["name"], r"^[a-z_]{1,64}$")
            self.assertEqual(tool["inputSchema"]["type"], "object")
            self.assertIn(tool["name"], desktop.PRESENT)

    def test_arguments_are_checked(self):
        self.assertEqual(desktop.validate("settings_set", {"key": "bar"}), "value is required.")
        self.assertEqual(desktop.validate("window_move", {"address": "1", "workspace": "2"}),
                         "workspace must be a whole number.")
        self.assertEqual(desktop.validate("app_open", {"app": "x", "extra": 1}), "Unknown argument extra.")
        self.assertEqual(desktop.validate("app_open", {"app": "Firefox"}), "")
        self.assertEqual(desktop.tool_name("mcp__cybexos__app_open"), "app_open")
        self.assertEqual(desktop.tool_name("mcp__other__app_open"), "")

    def test_policy_lets_the_service_decide_on_its_own_tools(self):
        self.assertEqual(policy.decide_tool("mcp__cybexos__window_close", {}, "/h").action, "allow")


class PromptTest(unittest.TestCase):
    def test_attachments_and_notes(self):
        text = prompt.turn_text("Why does this fail?", {"wide": True}, False, [
            {"kind": "window", "label": "Firefox · PR #1"},
            {"kind": "file", "label": "build.log", "text": "error: ```oops```"},
            {"kind": "image", "label": "paste.png"}])
        self.assertIn("The reply is shown in a wide view", text)
        self.assertIn("The person was looking at this window: Firefox · PR #1.", text)
        self.assertIn("Attached: build.log:\n````\nerror: ```oops```\n````", text)
        self.assertIn("1 image the person attached is included.", text)
        self.assertTrue(text.endswith("Why does this fail?"))
        self.assertIn("may only look", prompt.turn_text("q", look_only=True))
        self.assertIn("ATTENTION: yes", prompt.turn_text("q", routine="Monday check"))
        self.assertEqual(prompt.turn_text("plain"), "plain")


class ChangeLogTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="nas-"))
        self.home = self.root / "home"
        (self.home / ".config/cybexos").mkdir(parents=True)
        self.settings = self.home / ".config/cybexos/shell.json"
        self.settings.write_text(json.dumps({"bar": "solid", "assistantX": 10}))
        self.mode = "month"
        self.log = self.new_log()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.root, ignore_errors=True)

    def new_log(self):
        log = changes.ChangeLog(self.root / "changes", lambda: {"assistantHistory": self.mode}, self.home)
        log.load()
        return log

    def turn_writing(self, identifier, values=None, files=None):
        snapshots = policy.Snapshots(self.home)
        snapshots.begin()
        for path in (files or {}):
            snapshots.take(str(path))
        if values is not None:
            current = json.loads(self.settings.read_text())
            current.update(values)
            self.settings.write_text(json.dumps(current))
        for path, content in (files or {}).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        snapshots.finish()
        entries = self.log.from_snapshots(FakeTurn(identifier), snapshots)
        self.log.save()
        return entries

    def status(self):
        return {row["id"]: row for row in self.log.summaries()}

    def test_preferences_are_undone_one_at_a_time(self):
        [first] = self.turn_writing("t-1", {"bar": "transparent", "assistantX": 400})
        self.assertEqual((first["kind"], first["key"], first["before"], first["after"]),
                         ("setting", "bar", "solid", "transparent"))
        [second] = self.turn_writing("t-2", {"bar": "blur"})
        rows = self.status()
        self.assertEqual(rows[first["id"]]["status"], "blocked")
        self.assertEqual(rows[first["id"]]["blockedBy"]["id"], second["id"])
        self.assertEqual(rows[second["id"]]["status"], "applied")
        self.assertEqual(self.log.undo_local(self.log.get(second["id"])), "")
        self.log.mark_undone(self.log.get(second["id"]))
        self.assertEqual(json.loads(self.settings.read_text())["bar"], "transparent")
        self.assertEqual(self.status()[first["id"]]["status"], "applied")
        self.log.undo_local(self.log.get(first["id"]))
        settings = json.loads(self.settings.read_text())
        self.assertEqual((settings["bar"], settings["assistantX"]), ("solid", 400))

    def test_a_change_made_since_is_left_alone(self):
        [entry] = self.turn_writing("t-1", {"bar": "transparent"})
        self.settings.write_text(json.dumps({"bar": "blur"}))
        self.assertEqual(self.status()[entry["id"]]["status"], "changed")

    def test_a_new_key_is_removed_again(self):
        [entry] = self.turn_writing("t-1", {"clock24": True})
        self.assertFalse(entry["hadBefore"])
        self.log.undo_local(entry)
        self.assertNotIn("clock24", json.loads(self.settings.read_text()))

    def test_files_and_widgets_survive_a_restart(self):
        notes = self.home / "notes.txt"
        notes.write_text("before")
        plugin = self.home / ".local/share/cybexos/plugins/personal.cpu/manifest.json"
        entries = self.turn_writing("t-1", files={notes: "after", plugin: json.dumps({"id": "personal.cpu",
                                                                                         "name": "CPU"})})
        kinds = {entry["kind"]: entry for entry in entries}
        self.assertEqual((kinds["plugin"]["name"], kinds["plugin"]["op"]), ("CPU", "created"))
        self.assertEqual(kinds["file"]["path"], "~/notes.txt")
        self.log = self.new_log()
        self.assertEqual({row["status"] for row in self.log.summaries()}, {"applied"})
        for entry in self.log.entries:
            self.assertEqual(self.log.undo_local(entry), "")
        self.assertEqual(notes.read_text(), "before")
        self.assertFalse((self.home / ".local/share/cybexos/plugins/personal.cpu").exists())
        blobs = list((self.root / "changes" / "blobs").iterdir())
        self.assertTrue(all(oct(path.stat().st_mode & 0o777) == "0o600" for path in blobs))

    def test_nothing_is_saved_in_session_mode(self):
        self.mode = "session"
        self.log = self.new_log()
        notes = self.home / "notes.txt"
        notes.write_text("before")
        [entry] = self.turn_writing("t-1", files={notes: "after"})
        self.assertFalse((self.root / "changes" / "changes.json").exists())
        self.assertEqual(self.log.undo_local(entry), "")
        self.assertEqual(notes.read_text(), "before")


class RoutineScheduleTest(unittest.TestCase):
    def test_next_moments(self):
        at = datetime.datetime(2026, 11, 2, 10, 0)   # a Monday
        self.assertEqual(routines.due_after({"kind": "daily", "time": "09:00"}, at),
                         datetime.datetime(2026, 11, 3, 9, 0))
        self.assertEqual(routines.due_after({"kind": "weekly", "time": "09:00", "weekday": 0}, at),
                         datetime.datetime(2026, 11, 9, 9, 0))
        self.assertEqual(routines.due_after({"kind": "weekly", "time": "11:00", "weekday": 0}, at),
                         datetime.datetime(2026, 11, 2, 11, 0))
        self.assertEqual(routines.due_after({"kind": "monthly", "time": "10:00", "day": 1},
                                            datetime.datetime(2026, 12, 5)), datetime.datetime(2027, 1, 1, 10, 0))
        self.assertIsNone(routines.due_after({"kind": "update"}, at))

    def test_a_missed_run_happens_once(self):
        store = routines.Routines(Path(tempfile.mkdtemp(prefix="nas-")) / "routines.json")
        routine, error = store.create("Check this computer", {"kind": "daily", "time": "09:00"})
        self.assertEqual(error, "")
        routine["createdAt"] = routines.to_ms(datetime.datetime(2026, 11, 1, 12, 0))
        now = routines.to_ms(datetime.datetime(2026, 11, 5, 12, 0))
        self.assertEqual(store.due(now), [routine])
        routine["lastRun"] = now
        self.assertEqual(store.due(now + 60000), [])
        update, _ = store.create("What changed?", {"kind": "update"}, version="1.0.9")
        self.assertEqual(store.due(now, "1.0.9"), [])
        self.assertEqual(store.due(now, "1.0.10"), [update])

    def test_bad_schedules_and_the_attention_line(self):
        store = routines.Routines(Path(tempfile.mkdtemp(prefix="nas-")) / "routines.json")
        self.assertIn("HH:MM", store.create("q", {"kind": "daily", "time": "9"})[1])
        self.assertIn("weekday", store.create("q", {"kind": "weekly", "time": "09:00"})[1])
        self.assertEqual(routines.split_attention("ATTENTION: yes\nFirmware waits."), (True, "Firmware waits."))
        self.assertEqual(routines.split_attention("**ATTENTION: no**\nAll good."), (False, "All good."))
        self.assertEqual(routines.split_attention("No marker"), (None, "No marker"))


class LaneTest(ServiceTest):
    async def test_a_side_question_that_needs_a_change_waits_and_runs_next(self):
        main = await self.ask("hang")
        await self.client.until(lambda m: m["method"] == "turn.delta")
        side = await self.ask("edit the bar")
        self.assertEqual(side["lane"], "side")
        done = await self.client.finished(lane="side")
        self.assertTrue(done["needsChange"])
        queued = await self.client.until(lambda m: m["method"] == "queue.updated" and m["params"]["queue"])
        self.assertEqual((queued["params"]["queue"]["conversation"], queued["params"]["queue"]["reason"]),
                         (side["conversation"], "change"))
        self.assertIn("bar", json.loads((self.harness.home / ".config/cybexos/shell.json").read_text()))
        self.assertEqual(json.loads((self.harness.home / ".config/cybexos/shell.json").read_text())["bar"], "solid")
        self.client.notifications.clear()
        await self.client.result("turn.stop", {"lane": "main"})
        ran = await self.client.turn(lambda turn: turn["id"] not in (main["id"],) and turn["status"] == "completed")
        self.assertEqual((ran["conversation"], ran["queued"], ran["lookOnly"]), (side["conversation"], True, False))
        self.assertEqual(json.loads((self.harness.home / ".config/cybexos/shell.json").read_text())["bar"],
                         "transparent")
        self.assertEqual([change["key"] for change in ran["changes"]], ["bar"])

    async def test_claude_gets_the_tool_server_and_a_side_question_cannot_edit(self):
        await self.ask("hang")
        await self.client.until(lambda m: m["method"] == "turn.delta")
        await self.ask("again echo me")
        await self.client.finished(lane="side")
        runs = [entry["argv"] for entry in self.harness.entries() if entry.get("agent") == "claude"]
        main, side = runs[0], runs[1]
        config = json.loads(main[main.index("--mcp-config") + 1])
        server = config["mcpServers"]["cybexos"]
        self.assertEqual((server["type"], server["args"]), ("stdio", ["-m", "cybexos_assistant", "mcp"]))
        self.assertEqual(server["env"]["CYBEXOS_ASSISTANT_LANE"], "main")
        self.assertNotIn("--disallowedTools", main)
        start = side.index("--disallowedTools")
        self.assertEqual(side[start + 1:start + 5], ["Edit", "Write", "MultiEdit", "NotebookEdit"])
        self.assertEqual(json.loads(side[side.index("--mcp-config") + 1])["mcpServers"]["cybexos"]["env"]
                         ["CYBEXOS_ASSISTANT_LANE"], "side")

    async def test_one_question_waits_at_most(self):
        await self.ask("hang")
        await self.ask("hang")
        waiting = await self.client.result("turn.start", {"text": "third", "agent": "claude"})
        self.assertEqual(waiting["queued"]["text"], "third")
        busy = await self.client.call("turn.start", {"text": "fourth", "agent": "claude"})
        self.assertEqual(busy["error"]["code"], -32001)
        await self.client.result("queue.remove")
        hello = await self.client.result("hello", {"client": "test", "protocol": 1})
        self.assertIsNone(hello["queue"])
        self.assertEqual(hello["side"]["lane"], "side")


class AttachmentTest(ServiceTest):
    async def test_text_and_images_reach_the_agent(self):
        log = self.harness.home / "build.log"
        log.write_text("error: linker failed")
        await self.ask("echo me", attachments=[{"kind": "window", "label": "Kitty · build"},
                                               {"kind": "file", "path": str(log), "label": "build.log"},
                                               {"kind": "selection", "text": "line one"}])
        done = await self.client.finished()
        self.assertIn("The person was looking at this window: Kitty · build.", done["text"])
        self.assertIn("error: linker failed", done["text"])
        self.assertIn("Text the person selected", done["text"])
        binary = self.harness.home / "blob.bin"
        binary.write_bytes(b"\xff\xfe\x00")
        refused = await self.client.call("turn.start", {"text": "x", "agent": "claude",
                                                        "attachments": [{"kind": "file", "path": str(binary)}]})
        self.assertIn("Only text files and images", refused["error"]["message"])
        shots = self.harness.runtime / "cybexos" / "assistant"
        picture = shots / "paste-1.png"
        picture.write_bytes(b"\x89PNG\r\n\x1a\n")
        self.client.notifications.clear()
        await self.ask("image please", attachments=[{"kind": "image", "path": str(picture), "label": "paste.png"}])
        self.assertEqual((await self.client.finished())["text"], "image:image/png")
        self.assertFalse(picture.exists())


class DesktopCallTest(ServiceTest):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.shell = await FakeShell({
            "settings_set": {"ok": True, "result": {"key": "bar", "before": "solid", "after": "transparent"}},
            "window_info": {"ok": True, "result": {"title": "notes.txt — Editor", "app": "Editor"}},
            "app_open": {"ok": False, "error": "No app is called Nonesuch."},
        }).open(self.harness.socket)
        self.tools = await Client().open(self.harness.socket)

    async def asyncTearDown(self):
        await self.tools.close()
        await self.shell.close()
        await super().asyncTearDown()

    async def call(self, tool, arguments, lane="main"):
        return await self.tools.result("desktop.call", {"tool": "mcp__cybexos__" + tool, "arguments": arguments,
                                                        "lane": lane})

    async def test_tools_run_through_the_shell_and_are_listed_as_steps(self):
        idle = await self.call("settings_get", {})
        self.assertTrue(idle["isError"])
        await self.ask("hang")
        result = await self.call("settings_set", {"key": "bar", "value": "transparent"})
        self.assertEqual((result["isError"], json.loads(result["text"])["after"]), (False, "transparent"))
        self.assertEqual(self.shell.requests[-1], ("settings_set", {"key": "bar", "value": "transparent"}))
        failed = await self.call("app_open", {"app": "Nonesuch"})
        self.assertEqual((failed["isError"], failed["text"]), (True, "No app is called Nonesuch."))
        turn = await self.client.turn(lambda turn: len(turn["steps"]) >= 2)
        self.assertEqual([(step["label"], step["detail"], step["tool"]) for step in turn["steps"][:2]],
                         [("Changed a preference", "bar", True), ("Opened an app", "Nonesuch", True)])
        invalid = await self.call("window_move", {"address": "a1"})
        self.assertEqual(invalid["text"], "workspace is required.")

    async def test_a_side_question_may_only_look(self):
        await self.ask("hang")
        await self.ask("hang")
        looked = await self.call("settings_get", {}, lane="side")
        self.assertFalse(looked["isError"])
        refused = await self.call("settings_set", {"key": "bar", "value": "x"}, lane="side")
        self.assertTrue(refused["isError"])
        self.assertIn("may only look", refused["text"])
        side = await self.client.turn(lambda turn: turn["needsChange"], lane="side")
        self.assertTrue(side["lookOnly"])

    async def test_closing_a_window_always_asks_and_installs_ask_first(self):
        await self.ask("hang")
        closing = asyncio.create_task(self.call("window_close", {"address": "a1"}))
        card = (await self.client.turn(lambda turn: turn["approvals"]))["approvals"][0]
        self.assertEqual((card["title"], card["facts"][0]["value"]), ("Close this window?", "notes.txt — Editor"))
        await self.client.result("approval.respond", {"id": card["id"], "decision": "allow"})
        self.assertFalse((await closing)["isError"])
        self.assertEqual(self.shell.requests[-1], ("window_close", {"address": "a1"}))
        self.approval_policy("ask")
        await self.client.result("turn.stop")
        self.client.notifications.clear()
        await self.ask("hang")
        installing = asyncio.create_task(self.call("flatpak_install", {"id": "com.spotify.Client", "name": "Spotify"}))
        card = (await self.client.turn(lambda turn: turn["approvals"]))["approvals"][0]
        self.assertEqual(card["title"], "Install Spotify?")
        self.assertIn({"label": "For", "value": "Your account only"}, card["facts"])
        await self.client.result("approval.respond", {"id": card["id"], "decision": "deny"})
        self.assertTrue((await installing)["isError"])

    async def test_the_mcp_server_lists_and_forwards(self):
        listed = await mcp.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, self.harness.socket, "main")
        self.assertIn("settings_set", [tool["name"] for tool in listed["result"]["tools"]])
        hello = await mcp.handle({"jsonrpc": "2.0", "id": 2, "method": "initialize",
                                  "params": {"protocolVersion": "2025-03-26"}}, self.harness.socket, "main")
        self.assertEqual(hello["result"]["protocolVersion"], "2025-03-26")
        await self.ask("hang")
        called = await mcp.handle({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
            "name": "settings_set", "arguments": {"key": "bar", "value": "transparent"}}}, self.harness.socket, "main")
        self.assertFalse(called["result"]["isError"])
        self.assertIn("transparent", called["result"]["content"][0]["text"])
        unknown = await mcp.handle({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                                    "params": {"name": "rm_rf", "arguments": {}}}, self.harness.socket, "main")
        self.assertTrue(unknown["result"]["isError"])
        self.assertIsNone(await mcp.handle({"jsonrpc": "2.0", "method": "notifications/initialized"},
                                           self.harness.socket, "main"))


class ChangesServiceTest(ServiceTest):
    async def test_undo_from_the_log_and_after_a_restart(self):
        turn = await self.ask("edit the bar")
        done = await self.client.finished()
        [change] = done["changes"]
        self.assertEqual((change["key"], change["before"], change["after"], change["undoable"]),
                         ("bar", "solid", "transparent", True))
        listed = (await self.client.result("change.list"))["changes"]
        self.assertEqual([row["id"] for row in listed], [change["id"]])
        await self.client.close()
        await self.harness.stop()
        await self.harness.start()
        self.client = await Client().open(self.harness.socket)
        undone = await self.client.result("change.undo", {"id": change["id"]})
        self.assertEqual(undone, {"restored": [change["id"]], "skipped": []})
        shell = json.loads((self.harness.home / ".config/cybexos/shell.json").read_text())
        self.assertEqual(shell["bar"], "solid")
        again = await self.client.result("change.undo", {"id": change["id"]})
        self.assertEqual(again["skipped"][0]["id"], change["id"])
        self.assertEqual((await self.client.result("change.list"))["changes"][0]["status"], "undone")
        cleared = await self.client.result("conversation.clear")
        self.assertTrue(cleared["ok"])
        self.assertEqual((await self.client.result("change.list"))["changes"], [])
        self.assertTrue(turn["id"])


class RoutineServiceTest(ServiceTest):
    async def test_a_routine_runs_looks_only_and_reports(self):
        bad = await self.client.call("routine.create", {"question": "q", "schedule": {"kind": "daily"}})
        self.assertEqual(bad["error"]["code"], -32602)
        created = (await self.client.result("routine.create", {
            "question": "Send the routine report", "title": "Monday check",
            "schedule": {"kind": "weekly", "time": "09:00", "weekday": 0}}))["routine"]
        self.assertEqual((created["notify"], created["enabled"]), ("attention", True))
        started = await self.client.result("routine.run", {"id": created["id"]})
        self.assertEqual(started, {"started": True, "waiting": False})
        finished = await self.client.until(lambda m: m["method"] == "routine.finished")
        params = finished["params"]
        self.assertEqual((params["attention"], params["notify"], params["routine"]["title"]),
                         (True, True, "Monday check"))
        done = await self.client.finished()
        self.assertEqual((done["text"], done["lookOnly"], done["routine"]["id"]),
                         ("The SSD firmware update is waiting.", True, created["id"]))
        row = (await self.client.result("conversation.list"))["conversations"][0]
        self.assertEqual((row["routine"]["id"], row["title"]), (created["id"], "Monday check"))
        listed = (await self.client.result("routine.list"))["routines"][0]
        self.assertEqual((listed["last"]["attention"], listed["last"]["conversation"]), (True, row["id"]))
        self.assertGreater(listed["next"], 0)
        paused = (await self.client.result("routine.update", {"id": created["id"], "enabled": False}))["routine"]
        self.assertFalse(paused["enabled"])
        await self.client.result("routine.delete", {"id": created["id"]})
        self.assertEqual((await self.client.result("routine.list"))["routines"], [])

    async def test_a_routine_waits_for_a_busy_wiz(self):
        created = (await self.client.result("routine.create", {
            "question": "Send the routine report", "schedule": {"kind": "daily", "time": "08:00"}}))["routine"]
        await self.ask("hang")
        self.assertEqual(await self.client.result("routine.run", {"id": created["id"]}),
                         {"started": False, "waiting": True})
        await self.client.result("turn.stop")
        finished = await self.client.until(lambda m: m["method"] == "routine.finished")
        self.assertTrue(finished["params"]["attention"])


if __name__ == "__main__":
    unittest.main()
