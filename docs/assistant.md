# Cybex OS Assistant

The assistant is Wiz, a small character who floats above every window. Ask
him about Cybex OS by typing or by holding a key and talking; he answers in a
small box under himself. It can change desktop preferences, create personal widgets,
prepare system changes for review, write small programs and answer general
questions. The work is done by the coding agent the person already uses:
Claude Code or Codex. Cybex OS never stores their credentials.

The assistant is summoned, never proactive. It does not watch the screen,
listen or speak unless asked to for one question. Its notifications, its
situational suggestion and its routines all follow something the person did
or set up themselves.

## Using it

- **Connect an account first.** The welcome guide's Connect step offers it
  right after Hello (docs/welcome.md). When the selected agent is not signed in,
  opening the assistant shows setup with **Sign in to Claude Code** and
  **Sign in to Codex**. Each button opens that agent's own sign-in in your
  chosen terminal and browser. The box checks for completion automatically;
  **Check sign-in** also works after signing in elsewhere. Your draft stays
  in the box until you send it. Missing agents link to Software.
  Settings → Assistant also shows sign-in status. Automatic selection prefers
  an installed, signed-in agent.
- **Show or hide** the character from its menubar button (the sparkles beside
  the notifications) or with `cybex assistant toggle`. The button shows `…`
  while a question is being worked on, `!` while one needs your answer and a
  dot for a reply you have not seen. Shown, he flies in from the top-right
  corner of the screen to his place. Drag the character anywhere, including to
  another display. It stays where it was left, across sessions, and keeps out
  of the way while game mode is on. The welcome guide's own Wiz stands in for
  him while the guide covers the screen, and finishing the guide brings him
  out to his corner (docs/welcome.md).
- **Check this computer.** The box's first suggestion, Settings → Assistant,
  the welcome guide's Ready step and `cybexos-runtime ipc assistant check` all
  ask the same question. It tells the service this is a system check, so the
  agent starts from the read-only [`cybex doctor`](system-check.md), explains
  what it found and proposes fixes. Nothing changes until you agree; system
  changes are staged for review as below. The report goes to your AI provider
  as part of the question, like anything else the agent reads.
- **Ask** by clicking the character or tapping `Super+I`, then type and press
  Enter. Resting the pointer on him for half a second shows a one-line status
  under him: a reply ready, what he is working on, a question waiting for
  you, a routine's finding, or "Ask me anything". A pointer passing over him
  does nothing. Settings → Assistant → **When the pointer rests on Wiz**
  chooses Show status (default), Open the box (the box opens without taking
  the keyboard, as before) or Nothing.
- **Context besides the screenshot.** What goes with a question shows as
  removable chips above the field, and goes with that one question only:
  - the focused window's app and title, added when a new box opens
    (Settings → **Include the focused window**, on by default);
  - selected text: `Super+Shift+I` opens the box with the primary
    selection attached;
  - files and images dropped on Wiz (a ring shows where) or on the box, and
    images pasted with `Ctrl+V`. Images go to the agent as images; other
    files as text, up to 256 KB, and the service refuses anything that is
    neither. Dropped and pasted images are copied to the scratch folder and
    deleted with the answer, like screenshots.
- **Agent and model.** The chip under the field says who answers ("Claude
  Code · Opus") and opens a small menu to choose the agent and model for this
  conversation only; Settings keeps the default. A continued conversation
  keeps its agent (it greys the other: "Started with …"), so only its model
  can change. An agent that is not signed in offers **Sign in…**.
- **A suggestion that fits the moment.** The new box's first suggestion can
  follow what just happened: an update that failed ("Why did the update
  fail?", with what Software Update knows attached), a Cybex OS update that
  was kept ("What's new in 1.0.10?"), or a warning repeated three times in an
  hour in the notifications ("Why does "Wi-Fi disconnected" keep
  happening?"). A grey line says why it is there. It lasts an hour, until it
  is used, or until Wiz is asked something else; there is never more than
  one.
- **Each box is a conversation.** Clicking the character, tapping `Super+I`,
  Ask Wiz in the launcher and `cybex assistant ask` start a new conversation
  once the box has closed (a click elsewhere, `Esc`, the close button or the
  menubar button). The exception keeps an answer from getting lost: while a
  question is still running or waiting for your answer, or its answer has not
  been seen, Wiz opens that one instead. Hovering opens the box as it was
  left. **Reply** under an answer, or a conversation picked from History,
  continues it.
- **History.** The new box lists your three most recent conversations under
  the suggestions (fewer when the screen has no room); **History** opens them
  all in the box, grouped by day and searchable across questions and
  answers. A conversation still running says **Working**, one waiting for
  you **Your move**. Picking one shows its questions and answers above the
  field; what you type continues it with the agent it started with, even if
  Settings now prefers the other. Its **⋯** button offers **Continue in a
  terminal**, **Copy conversation**, **New conversation** and **Delete
  conversation**. History can be read while Wiz works on another question
  (the clock button on the working pill); a new question waits until he is
  free.
- **Deleting and clearing.** Hovering a row in History shows its delete
  button; the conversation goes at once and **Undo** brings it back until the
  box closes or another is deleted. **Clear history…** asks once, inside the
  box, and removes every conversation, stopping one still running (a change
  it already staged stays in Software Update). Only Wiz's history is
  cleared: Claude Code's and Codex's own session files stay, so their own
  `--resume` lists are untouched. Settings → Assistant → Conversations shows
  the count and opens or clears the history too.
- **Ask Wiz from the launcher.** When what you type in the launcher
  (`Super+Space`) matches no app or action, its one row is **Ask Wiz**, with
  your words quoted under him. Enter or a click closes the launcher and asks
  them, as typing them into the box would; the character comes out if it was
  hidden. Without a signed-in agent the question waits in the box behind the
  sign-in buttons. The row appears only for a plain query on the Apps list (a
  prefix such as `:` or `=` keeps its own results), and only while the
  assistant can answer: its service running, no other question in progress,
  and game mode off. Nothing about the screen is sent; if the box already
  holds a screenshot, the question waits there with it for you to send or
  detach.
- **Ask Wiz where things go wrong.** A failure notification (critical, or one
  that reads as an error) carries an **Ask Wiz** action, and Software
  Update's problem page an **Ask Wiz about this** button. Either opens the
  box with what that place knows attached as a chip and the question typed;
  nothing is sent until Enter. They show only while Wiz can answer.
- **Talk** by holding `Super+I` (or the microphone button) and releasing it to
  send. The words are transcribed locally by Voxtype, with dictation's
  speech model and languages ([dictation.md](dictation.md)); no audio leaves
  the computer. `Esc` or the cancel button discards a recording.
- **While it works** the character shows what it is doing (see
  [The character](#the-character)) and the box a short line about the
  current step. Clicking the character while it works tucks the box away;
  a blue dot appears when the reply is ready. `Super+I` brings the box back
  with its **Ask something else…** field.
- **A second question meanwhile** is answered alongside, in its own
  conversation, with permission only to look: read, search, the web, and
  read-only commands and desktop tools. If it needs to change something, it
  says what it would change and waits as **Up next**; Wiz asks it again,
  with changes allowed, as soon as the current question is done. **Run now**
  stops the current question first (after asking); × removes the waiting
  one. At most one question runs alongside and one waits; a question that
  continues the running conversation waits too.
- **A notification** says when a question that took longer than 20 seconds
  has finished, or when a question needs your answer, while the box was not
  in view on the screen you are using (hidden, tucked, another display, game
  mode). Its buttons are the reply's own (Add to bar, Review change…, Open);
  Open brings Wiz out with that conversation. Settings → **Notify when Wiz
  finishes**: When the box is closed (default), Always, Never. Focus and
  game mode keep it in the notification centre, as any notification.
- **Replies** stay under the character until closed. Copy, Reply (continue the
  conversation), Speak, and Terminal (Continue in a terminal: opens the same
  Claude Code or Codex session in Kitty, for longer coding work) appear under
  a reply, each with a visible label. A button drawn with only a glyph shows
  its name on hover or keyboard focus, and every button takes the pointer over
  at least 32 px. Each code block has its own **Copy** button.
- **What changed** is listed under the answer, one row each with its own
  Undo: a preference named as Settings names it, where it lives
  ("Appearance · Theme") and its old and new value ("Glass effect Off → On";
  a value the preferences file did not hold yet reads as the default it stood
  at, never "default"), a file, a widget, an app installed for this account,
  a routine. `settings_set` returns the same label and page, and the agent is
  asked to call the setting by that name in its answer.
  **Undo all** undoes every row that still can. A row that cannot be undone
  any more says why: it was changed again by a later answer (undo that one
  first), or changed since by something else, which is left as it is.
- **What Wiz did** lists the steps the agent took, in plain words with the
  file or command in grey; Cybex OS's own desktop tools carry the accent. It
  is folded after a short answer and open after a long one.
- **The wide view.** A reply too long for the box offers **Expand**, which
  opens it beside Wiz on the side of the screen with more room (about 560 ×
  640 at 1×; drag its inner edge to resize it). The agent is told the reply
  has room, so headings and tables are fine there. The choice stays until
  Collapse, and also applies to a conversation being read and to History.
- **Keeping out of the way.** Dragged near a corner or the middle of a side,
  he lands there (the spots show while dragging); anywhere else he stays
  exactly where he is dropped. Pushed past the left or right edge, he tucks
  away with only his hat brim and one eye showing; his pips still show,
  resting on him shows his status, and a click or `Super+I` brings him out.
  A pointer that sweeps across him without stopping makes him fade to a
  ghost and lets its clicks through to the window underneath, until it moves
  away or rests on him for half a second (Settings → **Fade while working
  under Wiz**, on by default).
- **From a terminal**, `cybex assistant ask "…"` asks the same assistant and
  prints the reply. With **Ask first** selected, approval cards appear on screen.
  `cybex assistant status` prints the service's state as JSON.
- **Screen context**, when enabled in Settings → Assistant, adds a screen
  button to the box. It attaches one screenshot of the display the character is
  on, taken with the character hidden, to that one question. The image is
  deleted when the reply finishes.

## What it may do without asking

Tool permissions default to **Always allow** for both Claude Code and Codex.
Commands, file edits and other tool requests proceed without permission cards,
including across conversations and service restarts. Settings → Assistant →
Tool permissions can select **Ask first** instead; the next question uses the
new choice without restarting the service.

The assistant still checks tool requests against its system ownership rules
(`desktop/assistant/cybexos_assistant/policy.py`). Administrator authentication
for staged system changes remains with polkit. The table below shows **Ask
first** behavior; **Always allow** automatically accepts its approval cards,
while refusals and Undo remain in effect:

| Action | Decision |
| --- | --- |
| Reading files, searching, web search and fetch | Allowed |
| Read-only commands (`ls`, `cat`, `rg`, `jq`, `hyprctl -j …`, `cybex update status`, `cybex plugin list`, `cybex shell status`, `systemctl --user status`, …) | Allowed |
| The system check (`cybex doctor`, `cybex doctor --json`; see [System check](system-check.md)) | Allowed |
| Editing desktop preferences (`~/.config/cybexos/…`) and personal plugins (`~/.local/share/cybexos/plugins/…`) | Allowed; the reply offers **Undo** |
| Staging a system change (`cybex update stage local`, `cybex software stage …`) | Allowed; administrator authentication is still requested by polkit |
| Applying a staged change (`cybex update apply …`) | A review card with the actual package changes; **Apply…** then asks for the administrator password |
| Vendor files (`/nix/store`, `/etc/cybexos`, `/run/current-system`) | Refused |
| `nixos-rebuild`, `sudo`, rebooting or powering off | Refused |
| Any other command or file edit | An approval card: Allow once, Allow for this conversation, or Deny |

The person's own agent settings still apply on top: a rule in
`~/.claude/settings.json` that already allows a tool is honored by Claude
Code. Codex runs with a read-only sandbox and routes write and escalation
requests through the assistant. **Always allow** answers each request
automatically, so ownership checks still run on subsequent requests.

New widgets are created disabled. When a reply created one, **Add to bar**
enables it with `cybex plugin enable`.

## Desktop tools

Both agents get Cybex OS's own tool server, `cybexos`
(`desktop/assistant/cybexos_assistant/mcp.py`, started by the agent as
`cybexos-assistant mcp` for the assistant's own processes only). Its tools
apply live, check values, and record every change for Undo:

| Tool | What it does | Without asking |
| --- | --- | --- |
| `desktop_status`, `settings_search`, `settings_get`, `wallpaper_search`, `software_search`, `doctor_run`, `routine_list` | Look: windows, workspaces, displays, theme; settings with their values; Wallhaven; Flathub; the system check; routines | Yes, also alongside and in routines |
| `settings_set`, `wallpaper_set` | Change a preference (checked exactly as the Settings window checks it; the assistant's own settings are refused) or the wallpaper (a Wallhaven image is downloaded into the wallpaper folder) | Yes; listed under Changed |
| `routine_create`, `routine_delete` | Create or remove a routine | Yes; listed under Changed |
| `app_open`, `window_focus`, `window_move`, `workspace_switch` | Open an app, focus or move a window, show a workspace | Yes |
| `window_close` | Close a window | **Always asks**, even under Always allow: the app may have unsaved work |
| `flatpak_install`, `flatpak_remove` | Install or remove a Flathub app for this account (`cybex software flathub`), waiting until it is done | Asks under Ask first; listed under Changed, and Undo removes or reinstalls it |

The service decides on every call itself (`server.desktop_call`); the
agents' own permission prompt for these tools is always answered yes. Tools
that only the desktop can carry out (preferences, the wallpaper, windows,
apps) go to the shell as `desktop.request` and are answered by
`Common/AssistantTools.qml`. The shell and terminal stay available for
everything else, under the policy table above.

## Changes and Undo

Everything Wiz changes is recorded in a change log
(`desktop/assistant/cybexos_assistant/changes.py`). A preference changed
in `shell.json` becomes one entry per key, by its value rather than its
bytes, so the shell rewriting the file does not stop Undo; a widget is one
entry for its folder; other files one entry each, with the earlier version
kept on disk (0600) so Undo survives a restart of the service. Apps, routines
and staged system changes (which Software Update owns and undoes) are entries
too. Settings → Assistant → **Changes Wiz made** lists them by day, links each
to its conversation, and offers Undo, Remove or Delete while it can still be
undone. The log follows **Keep conversations**: 30 days, forever, or nothing
saved; clearing the history clears it too.

## Routines

A routine is a question Wiz asks on a schedule: every day, every week on a
day, every month on a day (1–28) at a time, or after each kept Cybex OS
update. Create one by asking ("every Monday morning, check this computer"),
which the agent does with `routine_create` and the reply shows as a
**Routine created** card, or in Settings → Assistant → **Routines**, where
each can also be run now, paused, edited or removed.

A routine runs only while the person is logged in, when Wiz is free; one
missed while the computer was off runs once at the next chance. It only
looks: its question may not change anything, and fixes wait for the person
in its conversation, which History marks with a calendar. Its reply starts
with a verdict line the service reads and removes. With a finding, or always
when the routine says so, a notification follows and Wiz shows the amber pip
until the conversation is opened; with nothing to report, only History has
the run. Routines are kept in `routines.json` beside the conversations, whatever
**Keep conversations** says.

## Settings

Settings → Assistant, stored in `~/.config/cybexos/shell.json`:

| Key | Values | Default |
| --- | --- | --- |
| `assistantAgent` | `auto`, `claude`, `codex` | `auto` (the `cybex agent` default when it is Claude Code or Codex, else whichever is installed) |
| `assistantApprovalPolicy` | `always` (Always allow), `ask` (Ask first) | `always` |
| `assistantClaudeModel` | `default`, `fable`, `sonnet`, `opus` | `default` |
| `assistantCodexModel` | `default`, `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.6-sol` | `default` |
| `assistantSpeak` | spoken replies | `false` |
| `assistantScreenContext` | offer the screen button | `false` |
| `assistantHistory` | keep conversations and the change log: `month` (30 days), `forever`, `session` (until you log out; nothing saved) | `month` |
| `assistantNotify` | notify when a question finishes or waits: `closed` (while the box is not in view), `always`, `never` | `closed` |
| `assistantHover` | resting the pointer on Wiz: `status`, `open` (the box), `nothing` | `status` |
| `assistantFade` | fade and let clicks through while the pointer sweeps over him | `true` |
| `assistantWindowContext` | a new question carries the focused window's app and title | `true` |
| `assistantExpanded`, `assistantExpandedWidth` | the wide view, and its width (420–1200) | `false`, `560` |
| `assistantTuck` | the screen edge he is tucked behind: `""`, `left`, `right` | `""` |
| `assistantShown` | the character is on screen | `false` |
| `assistantScreen`, `assistantX`, `assistantY` | where it was left | primary display, top right |

### The character

Wiz is a small figure in a charcoal cloak under an oversized, slightly
crooked hat with the red Cybex band. His face stays in shadow and two glowing
eyes carry the expression. He follows the assistant's turn:

| Pose | When |
| --- | --- |
| Listening | the box is open, or you are talking (the hat rises with your voice) |
| Thinking | a question is being worked on; runes circle the hat |
| Working | a tool is at work (a command, an edit); a spell glows in front of him |
| Needs input | a question waits for your answer; he peeks from under the brim and an amber pip pulses |
| Finished | an answer arrived: happy eyes, a nod and a short sparkle |
| Carried | you are dragging him (see below) |
| Happy, sorry, asleep | speaking; a failed reply; the assistant service is not running |
| Idle | everything else |

Dragging him is a small panic. Picked up, he jumps, his hat pops off, "?!"
flashes, sweat flies and his feet come out from under the cloak, kicking.
While you move him he swings from where you hold him, his bottom trailing,
and follows the pointer's speed and direction: pulled sideways, his hat and
its tip blow back, his feet trail and his eyes look ahead; lifted, the hat is
shoved down over his eyes; dropping, it floats off above him while he stares
up at it. A diagonal drag combines both and stretches him along it. Held
still, he trembles and sweats. A few quick back-and-forths make him dizzy:
spiral eyes, his hat askew and stars circling it, for about two seconds after
he is put down. Dropped, he lands with a thud, eyes squeezed shut and a puff
of dust, harder the faster he was moving; his hat lands a beat later,
crooked, and he shakes it straight.

A blue pip marks a reply you have not seen, as the menubar dot does. His eyes
follow the pointer while it rests on him.

Wiz is cheap to keep on screen. He is drawn from still layers
(`desktop/quickshell/assets/wiz/`), each rendered once at its final size and
then only moved: no canvas, and no per-frame script except while he is being
dragged. The overlay covers the whole
display, so every frame he draws is a frame of the display. Idle, he holds
still between blinks, glances and a rare wobble of the hat: a few frames a
second, against sixty for a canvas redrawn every frame. Continuous
motion is reserved for a running turn, recording and a drag; after a drop he
is still again within about three seconds. A waiting question
pulses three times, then once every eight seconds. With reduced motion, the
power saver profile or an idle session he holds each pose still, and nothing
runs while he is hidden.

His artwork, poses and timing live in `Common/WizRig.js`. After changing it,
run `scripts/export-wiz` to rebuild the layers, the still poses in
`assets/wiz/` and the installer's pictures; the tests fail while they are out
of date.

### Wiz elsewhere

The same character shows the state of the system's other long or uncertain
moments, and each pose means the same thing everywhere: thinking is checking,
working is changing something, the amber pip is your move, listening is a
question to you, sorry is a failure and asleep is nothing available. He speaks
only once, in the welcome guide's hello; everywhere else he only shows.

| Where | What he shows |
| --- | --- |
| Installer ([installation](installation.md)) | the system check (thinking, happy, or the amber pip), the installation (working), done (finished), stopped or failed |
| Welcome guide ([welcome](welcome.md)) | a greeting on Hello, asleep on Connect until an agent is signed in, the system check on Ready, then the hop to his corner |
| Software Update ([updates](updates.md)) | every status page, and What's New once a new Cybex OS version is kept |
| Launcher | **Ask Wiz** when nothing matches |
| Notifications | the empty notification centre; asleep under Focus |
| Disk unlock at boot, lock screen, kitty's fastfetch ([branding](branding.md)) | still pictures: asleep, listening as you type, sorry or happy at unlock |

He stays out of permission prompts, the installer's disk choice and erase
review, Settings pages, the update review, the menubar, notification toasts,
the boot menu and the recovery desktop. While the welcome guide fills the
screen, its Wiz is the only one: the corner Wiz waits and takes over when the
guide closes.

The menubar, boot splash and documents use the corresponding logo assets
from [the brand directory](../assets/brand/README.md).

## Installation

`cybexos.features.assistant` (default on) installs the service. Codex is part
of every installation, and Claude Code of every installation with proprietary
applications, whatever the assistant and developer tooling choices. Voxtype,
Pipewire and speech-dispatcher are part of every installation too. Turning the feature off removes the menubar button,
the shortcut and the service; nothing in `shell.json` is lost.

## Architecture

- `desktop/assistant/cybexos_assistant/` — the `cybexos-assistant` service, a
  user unit (`cybexos-assistant.service`). It owns the agent processes so a
  Quickshell restart, including one caused by the assistant's own changes,
  does not end a turn. Activation never restarts the service itself: after
  an update changed its unit it restarts into the new one once idle, or at
  the next login when conversations are kept only for the session
  ([Updates](updates.md#desktop-services-during-activation)). Only the
  standard library is used.
  - `server.py` — the socket and the session state.
  - `auth.py` — bounded, output-discarding `claude auth status` and
    `codex login status` checks. No prompt or model request checks sign-in.
    Login runs `claude auth login` or `codex login` in the background, with
    no terminal: each opens the browser and waits for it on localhost. The
    shell discards their output, which can name the account, and offers
    **Cancel sign-in** while one waits. Credentials remain with the provider
    CLI, outside the assistant and store.
  - `claude.py` — Claude Code over `--input-format stream-json` with
    `--permission-prompt-tool stdio`: every permission prompt arrives as a
    `can_use_tool` control request and is answered automatically by default,
    or through a card with **Ask first** selected.
  - `codex.py` — `codex app-server` (JSON-RPC over stdio): threads, turns,
    and `item/*/requestApproval` server requests.
  - `policy.py` — the table above, and the file snapshots behind Undo.
  - `speech.py` — speech-dispatcher's SSIP socket, one sentence per message
    so the reply can follow along.
  - `prompt.py` — the instructions appended to the agent's own system
    prompt, and the per-question notes (attachments, looking only, a
    routine, the wide view).
  - `changes.py` — the change log behind Undo.
  - `routines.py` — routines and their schedules.
  - `desktop.py` — the desktop tools: schemas, kinds and step labels.
  - `mcp.py` — the tools as an MCP server, which forwards each call to the
    service as `desktop.call`.
- `desktop/quickshell/Common/Assistant.qml` — the shell's client: connection,
  turn state, voice, screen capture, attachments, notifications and
  placement. `Common/AssistantTools.qml` carries out the desktop tools only
  the shell can.
- `desktop/quickshell/AssistantWindow.qml` and `Assistant/` — the overlay
  surface, the character, the composer, the working pill and the reply card.
- `desktop/quickshell/Bar/Modules/Assistant.qml` — the menubar button.

State lives in `~/.local/state/cybexos/assistant/`: `state.json` keeps the
last answer for the box (only while its conversation exists and
conversations are saved), `conversations/<id>.json` (directory `0700`,
files `0600`, `history.py`) holds one conversation each: its agent, the
agent's session id, its title (the first question, or the routine's), the
routine that started it, and every question with its answer, status, times
and steps. `changes/` holds the change log and the earlier versions of files
it can restore, and `routines.json` the routines. Screenshots and approval cards are never
stored; screenshots live in `$XDG_RUNTIME_DIR/cybexos/assistant/` only for
the question that used them. The service applies `assistantHistory` when it
starts and whenever it lists conversations: with `month` it forgets
conversations untouched for 30 days, with `session` it removes the stored
files and keeps conversations in memory only. At most 500 are kept, the
oldest going first. Clearing removes the files and the kept answer.

### Protocol

`$XDG_RUNTIME_DIR/cybexos/assistant.sock` (directory `0700`) carries JSON-RPC 2.0,
one UTF-8 JSON object per line. Every connected client receives every
notification. Lines are limited to 4 MiB.

Requests:

| Method | Params | Result |
| --- | --- | --- |
| `hello` | `{client, protocol: 1}` | `{protocol, agents, turn, conversations, speech}` |
| `auth.status` | `{}` | `{agents}` — refresh installation/sign-in status |
| `auth.login` | `{agent: "claude" \| "codex"}` | `{argv, cwd}` — the agent's own login command, which the shell runs in the background |
| `turn.start` | `{text, agent, model?, conversation?, screenshot?, attachments?, context?}` | `{turn}` (its `lane` says whether it runs in the main lane or alongside), or `{queued}` when it waits; error `-32001` once one question already waits, `-32002` for a conversation no longer in the history. Without `conversation` the question starts a new one; with it, it continues that conversation with its own agent |
| `turn.stop` | `{lane?}` | `{stopped}`; `lane` is `main` (default) or `side` |
| `queue.remove`, `queue.run` | `{}` | `{ok}` — drop the waiting question, or stop the main one so it starts now |
| `change.list` | `{}` | `{changes: [entry]}`, newest first, each with `status` (`applied`, `undone`, `blocked` with `blockedBy`, `changed`, `system`) and `undoable` |
| `change.undo` | `{id}` or `{ids}` | `{restored: [id], skipped: [{id, reason}]}` |
| `routine.list`, `routine.create`, `routine.update`, `routine.delete`, `routine.run` | a routine's `{question, title?, schedule, notify?, enabled?}` or `{id}` | `{routines}`, `{routine}`, `{ok}`, or `{started, waiting}` |
| `desktop.call` | `{tool, arguments, lane}` | `{isError, text}` — from mcp.py |
| `desktop.respond` | `{id, ok, result?, error?}` | `{ok}` — the shell's answer to `desktop.request` |
| `approval.respond` | `{id, decision: "allow" \| "always" \| "deny"}` | `{ok}` |
| `turn.undo` | `{id}` | `{restored: [path], skipped: [path]}` — every change of that answer that can still be undone |
| `conversation.list` | `{query?}` | `{conversations: [summary]}`, newest first; `query` matches titles, questions and answers without case |
| `conversation.open` | `{id}` | `{conversation}`: the summary with `turns` (`id, prompt, text, status, error, errorKind, startedAt, finishedAt`) and `resumable` |
| `conversation.delete` | `{id}` | `{ok}`; stops its running question first |
| `conversation.restore` | `{id}` | `{conversation: summary}` — the one deleted last only |
| `conversation.clear` | `{}` | `{ok}`; stops a running question, removes every conversation and the kept answer |
| `conversation.handoff` | `{id?}` | `{argv, cwd}` — the terminal command that resumes that conversation's session (default: the latest answer's) |
| `speech.say` | `{text, language?}` | `{id, sentences}` |
| `speech.stop` | `{}` | `{ok}` |

`agents` is `{claude: {available, label, auth}, codex: {available, label, auth}}`.
`auth` is `ready`, `required`, `unknown` (the bounded status check failed), or
`missing`. Status output and credentials are never exposed through this
protocol or saved in assistant state. `turn.start` returns `-32004` before
starting a model when the selected installed agent needs sign-in. A CLI that
rejects an existing credential also marks that agent as requiring sign-in.
`context` is `{output, speak, language, purpose?}`: the display the question
was asked on, whether the reply will be spoken (the agent then keeps it short
and avoids tables and code), and the shell's language. `purpose:
"system-check"` marks a question asking the assistant to check this computer:
the turn's note tells the agent to run `cybex doctor --json` first, follow the
skill's system check reference, and propose fixes without changing anything
until the person agrees. Any other `purpose` is ignored. The system prompt is
the same for every turn.

Notifications:

- `turn.updated {turn, lane}` — a complete snapshot after any change except
  text; `null` after the history was cleared.
- `conversations.updated {conversations}` — the summaries after a question
  starts or finishes, or a conversation is deleted, restored, cleared or
  pruned.
- `agents.updated {agents}` — refreshed installation/sign-in status.
- `turn.delta {id, text, lane}` — reply text appended while streaming.
- `queue.updated {queue}`, `changes.updated {count}`, `routines.updated {routines}`.
- `routine.finished {routine, conversation, attention, notify, summary}`.
- `desktop.request {id, tool, arguments}` — to the shell only.
- `notice {text}` — something the box should say (a waiting question that
  could not start).
- `speech.progress {id, index}`, `speech.done {id, status}`.

A turn snapshot:

```json
{
  "id": "t-3f2a…",
  "agent": "claude",
  "prompt": "Make the menubar transparent",
  "status": "running | waiting | completed | stopped | failed",
  "step": "Editing shell.json",
  "text": "…",
  "error": "",
  "errorKind": "auth | missing | crashed | ''",
  "approvals": [{"id": "a-1", "kind": "command | edit | apply | other",
                  "title": "Run a command", "detail": "…", "command": "…",
                  "path": "…", "diff": "…", "transaction": "…", "changes": "…",
                  "ready": true}],
  "startedAt": 1761223000000,
  "finishedAt": 0,
  "undo": ["~/.config/cybexos/shell.json"],
  "changes": [{"id": "ch-…", "kind": "setting", "key": "barOpacity", "before": 1, "after": 0.8,
               "status": "applied", "undoable": true}],
  "steps": [{"label": "Changed a preference", "detail": "barOpacity", "tool": true}],
  "routines": [],
  "lane": "main",
  "lookOnly": false,
  "needsChange": false,
  "routine": null,
  "plugins": [{"id": "personal.cputemp", "name": "CPU temperature"}],
  "staged": "8f3a2c…",
  "screenshot": false,
  "resumable": true,
  "conversation": "c-5d1e…"
}
```

A conversation summary:

```json
{
  "id": "c-5d1e…",
  "agent": "claude",
  "title": "Why is my Wi-Fi dropping after suspend?",
  "preview": "Power saving turns back on when the card resumes…",
  "status": "completed",
  "turns": 2,
  "createdAt": 1761223000000,
  "updatedAt": 1761223400000
}
```

`ready` (apply cards only) is true when the lifecycle status shows that
transaction built and checked. Errors: `-32001` busy, `-32002` no such
pending approval, nothing to undo, or no such conversation, `-32003` nothing to resume, `-32602`
invalid params (including a screenshot outside
`$XDG_RUNTIME_DIR/cybexos/assistant/`, which the service creates `0700` and
empties when it starts), `-32601` unknown method.

The service never replays a request after a reconnect; the shell sends
`hello` and adopts the snapshot it returns.

Authentication commands follow the official [OpenAI authentication
documentation](https://developers.openai.com/codex/auth/) and [Claude Code CLI
reference](https://code.claude.com/docs/en/cli-reference).
