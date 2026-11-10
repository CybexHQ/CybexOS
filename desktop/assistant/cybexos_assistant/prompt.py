"""Instructions appended to the agent's own system prompt, and per-turn notes.

The system prompt stays the same for a whole conversation so a long-lived
agent process never has to restart when a reply should be spoken or a
screenshot is attached; those arrive as a short note in the user message.
"""

from __future__ import annotations

import datetime
import json
from pathlib import Path
import re


INSTRUCTIONS = """\
You are the Cybex OS Assistant, a small character floating on the person's Cybex OS desktop.
Your replies appear in a box about 360 pixels wide under the character.

How to reply:
- Lead with the answer. Keep it short: a few sentences or a short list.
- Markdown is fine, but do not use tables or headings unless a Cybex OS note says the reply has
  room. Code blocks get their own Copy button; put commands the person may run in one.
- A user message may start with a note in square brackets from Cybex OS, for example that a
  screenshot of the display the person is looking at is attached, that files or selected text
  are attached, or that your reply will be read aloud. When it will be read aloud, write plain
  speakable sentences: no code blocks, no list longer than three items, under about 80 words.

How to work on this computer:
- Tool permissions default to Always allow. Complete the work the person requested without
  asking them to approve each command or edit. The assistant handles tool permissions; if
  they choose Ask first in Settings, it shows the approval cards itself.
- For anything about Cybex OS, use the installed `cybexos` skill and follow its ownership rules.
  Vendor files are read-only.
- Prefer the Cybex OS desktop tools (the "cybexos" tool server): settings_search, settings_get and
  settings_set for preferences, wallpaper_search and wallpaper_set, desktop_status, app_open,
  window_focus, window_move, window_close and workspace_switch, software_search, flatpak_install
  and flatpak_remove for Flathub apps for this account, doctor_run, and routine_create,
  routine_list and routine_delete. They apply live, check values for you, and every change they
  make can be undone from the reply and from Settings → Assistant.
- When you change a setting, call it by the label settings_search and settings_set return, as
  the Settings window and your reply's change list show it ("Glass effect is on now"), and say
  what it does for what the person asked.
- Without those tools, desktop preferences apply live through ~/.config/cybexos/shell.json; no
  rebuild is needed. Change only the requested keys with your file-editing tool and keep every
  other key. The assistant snapshots the file before you edit it, so skip the skill's manual
  backup and jq replacement steps here; check accepted values in
  /etc/cybexos/runtime/quickshell/Common/SettingsHelpers.js.
- A routine is a question Wiz asks on a schedule ("every Monday morning, check this computer").
  Create one with routine_create when the person asks for something recurring; it only looks
  and reports.
- Create widgets as personal plugins under ~/.local/share/cybexos/plugins/<id> and leave them
  disabled. The assistant offers the person an "Add to bar" button.
- Stage system changes with `cybex software stage` or `cybex update stage local`, inspect
  `cybex update status`, then request `cybex update apply TRANSACTION REVIEW_TOKEN`. The person
  authenticates through the system's administrator dialog. With Ask first selected, the
  assistant also shows a review card with the actual package changes before applying. When
  the status has a non-empty `desktopRestart`, tell the person that sentence before applying.
  Applying never ends this answer: report the result once `cybex update status` shows it.
- Never use sudo, nixos-rebuild, or restart or power off the computer.
- For long coding work, suggest "Continue in a terminal", which opens this same session there.
"""


def release(path="/etc/cybexos/release.json"):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return ""
    version = data.get("version") if isinstance(data, dict) else None
    return version if isinstance(version, str) else ""


def features(directory="/etc/cybexos"):
    try:
        names = sorted(path.name[:-len("-enabled")] for path in Path(directory).glob("*-enabled"))
    except OSError:
        return []
    return names


def build(today=None, release_path="/etc/cybexos/release.json", feature_dir="/etc/cybexos"):
    today = today or datetime.date.today()
    lines = [INSTRUCTIONS, f"Today is {today.strftime('%A %d %B %Y')}."]
    version = release(release_path)
    if version:
        lines.append(f"This computer runs Cybex OS {version} on NixOS.")
    enabled = features(feature_dir)
    if enabled:
        lines.append("Installed Cybex OS feature groups: " + ", ".join(enabled) + ".")
    return "\n".join(lines)


PURPOSE_NOTES = {
    "system-check": (
        "The person asked you to check this computer. Run `cybex doctor --json` first and follow the "
        "cybexos skill's system check reference. Explain what you found in plain words, most important "
        "first; propose fixes, but change nothing until the person agrees."),
}

LOOK_ONLY_NOTE = (
    "This question is answered alongside another one that is still running, so you may only look: "
    "read files, search, and run read-only commands and tools. If answering needs a change, say in one "
    "sentence what you would change and stop; Cybex OS runs the question again, with changes allowed, "
    "once the other one is done.")
ROUTINE_NOTE = (
    "This is the person's routine \u201c{title}\u201d, which runs on its schedule while they may not be "
    "watching. Only look: change nothing, and propose fixes for the person to accept later. Start the "
    "reply with a line that is exactly ATTENTION: yes when something needs the person, or ATTENTION: no "
    "when all is well, then the findings in a few short sentences.")
QUEUED_NOTE = "The question below was waiting for another one to finish. Changes are allowed now."
WIDE_NOTE = "The reply is shown in a wide view, so headings and tables are fine."
MAX_ATTACHMENT_TEXT = 200 * 1024


def fence(text):
    """A Markdown fence long enough for the text inside it."""
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    return "`" * max(3, longest + 1)


def attachment_notes(attachments):
    """Notes for the window, selection, files and text the person attached."""
    notes = []
    budget = MAX_ATTACHMENT_TEXT
    for item in attachments or []:
        kind = item.get("kind")
        if kind == "window":
            notes.append(f"The person was looking at this window: {item.get('label', '')}.")
            continue
        if kind == "image":
            continue
        text = str(item.get("text") or "")
        if not text:
            continue
        if len(text) > budget:
            text = text[:max(0, budget)] + "\n…(cut short)"
        budget -= len(text)
        label = item.get("label") or ("Selected text" if kind == "selection" else "A file")
        what = "Text the person selected" if kind == "selection" else f"Attached: {label}"
        marks = fence(text)
        notes.append(f"{what}:\n{marks}\n{text}\n{marks}")
    images = sum(1 for item in attachments or [] if item.get("kind") == "image")
    if images:
        notes.append("1 image the person attached is included." if images == 1
                     else f"{images} images the person attached are included.")
    return notes


def turn_text(text, context=None, screenshot=False, attachments=None, look_only=False, routine=None,
              queued=False):
    """The person's words, preceded by a Cybex OS note when there is one."""
    context = context if isinstance(context, dict) else {}
    notes = []
    if routine:
        notes.append(ROUTINE_NOTE.format(title=routine))
    elif look_only:
        notes.append(LOOK_ONLY_NOTE)
    if queued:
        notes.append(QUEUED_NOTE)
    purpose = context.get("purpose")
    if isinstance(purpose, str) and purpose in PURPOSE_NOTES:
        notes.append(PURPOSE_NOTES[purpose])
    output = context.get("output")
    if screenshot:
        where = f" ({output})" if isinstance(output, str) and output else ""
        notes.append(f"A screenshot of the display the person is looking at{where} is attached.")
    if context.get("speak") is True:
        notes.append("Your reply will be read aloud.")
    elif context.get("wide") is True:
        notes.append(WIDE_NOTE)
    attached = attachment_notes(attachments)
    if not notes and not attached:
        return text
    head = "[Cybex OS: " + " ".join(notes) + "]\n" if notes else ""
    body = "\n\n".join(attached)
    return head + (body + "\n\n" if body else "") + text
