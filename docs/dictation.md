# Dictation

Press **F9** (or **Super+Ctrl+X**, or the microphone mute key) and speak.
A pill at the bottom of the screen shows your words as you say them. Press
the key again to stop: the finished words are tidied up and typed into the
window you were using, which keeps its focus the whole time. A click on the
pill also stops it. The menubar's microphone action does the same; a middle
click on it, or **Super+Ctrl+Shift+X**, opens the [history](#history).

Dictation comes with the developer tooling feature
(`cybexos.features.developer`, default on). Speech is recognised on this
computer by [Voxtype](https://github.com/peteonrails/voxtype) with OpenAI's
Whisper models or NVIDIA's Parakeet; no audio leaves it. The assistant's
push-to-talk (Super+I) uses the same daemon and settings
([assistant.md](assistant.md)).

## First use

The first dictation works straight away with the small Whisper model built
into every installation (`base`, 142 MB, in `/etc/cybexos/models`). Once it
has typed its words, a card appears where the pill was:

- **Make dictation more accurate** offers the model that suits your
  languages: **Fast & accurate** (Parakeet, 639 MB download) when both are
  among the 25 European languages it knows, otherwise **Accurate** (Whisper
  large-v3-turbo, 834 MB). Either recognises names, technical words and
  languages other than English much better, and runs locally.
- **Do you also dictate in another language?** English is the default.
  Choosing a second language makes Whisper decide, each time, which of your
  two languages you are speaking. One key covers both.

**Not now** keeps the built-in model. The card appears once; everything on it
is also in **Settings → Assistant → Dictation**. It never takes the keyboard
until you click it, so it cannot catch words meant for your window.

## Settings

**Settings → Assistant → Dictation** (the menubar indicator's settings and
`cybexos-runtime ipc dictation settings` link there). The values are the
indicator's module options (`modOpts.indicators.dictation*` in `shell.json`).

- **Speech**
  - **Language** and **Second language** (or None).
  - **Speech model**, three cards:

    | Card | Model | Size | Languages |
    | --- | --- | --- | --- |
    | Standard | Whisper `base`, built in | 142 MB | 99 |
    | Accurate | Whisper large-v3-turbo, 8-bit | 834 MB download | 99 |
    | Fast & accurate | Parakeet TDT 0.6B v3, 8-bit | 639 MB download | 25 European |

    Choosing one that is not downloaded starts the download; the card shows
    its progress, and **Remove …** deletes it again (dictation returns to the
    built-in model first). Fast & accurate is marked *Best* and offered only
    when both languages are among Parakeet's: Bulgarian, Croatian, Czech,
    Danish, Dutch, English, Estonian, Finnish, French, German, Greek,
    Hungarian, Italian, Latvian, Lithuanian, Polish, Portuguese, Romanian,
    Russian, Slovak, Slovenian, Spanish, Swedish and Ukrainian (and Maltese,
    which the shell does not offer). It tells them apart by itself; a later
    change to a language it does not know falls back to Accurate, or
    Standard. It cannot take the names and terms below.
  - **Live text**: words in the pill while you speak (default on). It keeps
    the speech model loaded so the words can follow you; off, the model
    loads when a dictation starts and is released afterwards, and the words
    arrive when you stop.
- **Words**
  - **Names and terms**: chips the Whisper models should expect (their
    initial prompt, one line of at most 400 characters).
  - **Corrections**: *When I say* → *Write*. Whole words, in any case, for
    every model: they are applied to the live words in the pill and to the
    typed text. Up to 200.
  - A suggestion appears when you have made the same fix to two dictations
    in the history (**Correct**, the pencil): *You changed "voxtipe" to
    "Voxtype" 2 times. Always write it that way?* **Add** makes it a
    correction; **No** stops suggesting it. Only edits made in the history
    count; other apps' text is never read.
- **Tidy up**: **Off** (the words as heard), **Basic** (default) or
  **Polish**; see [Tidy-up](#tidy-up). **Polish with** chooses Claude Code
  or Codex. **Leave terminals and code editors alone** (on) types exactly
  what you said where text is taken literally.
- **History**: **Keep dictations** for 30 days (default), Forever or Don't
  save; **Keep recordings** (off) saves each dictation's audio too.
  **Open history** and **Clear history**.

## Tidy-up

After the model has finished, the corrections are applied and the words are
tidied before they are typed:

- **Basic** runs in the helper, instantly: hesitations (um, uh, erm, hmm;
  eh and ehm in Dutch; äh in German; euh in French) go, with the comma
  around them, a sentence that began with one begins with the next word,
  English "i" becomes "I", spaces before punctuation go, and a phrase of
  three or more words ends with a full stop. Models already write capitals
  and punctuation, so most dictations come out as said.
- **Polish** first does the same, then sends the text (never the recording)
  to the person's own coding agent once, to rewrite it into clean sentences
  in the same language and follow self-corrections ("tomorrow, no wait,
  Friday"): `claude -p --no-session-persistence --tools "" --model haiku`
  or `codex exec --ephemeral --sandbox read-only`, so it has no tools and
  leaves no session behind. The instructions forbid answering or carrying
  out what was said; a reply more than twice as long as the dictation is
  refused, and the reply is typed as one line (a line break would be typed
  as Enter). It takes two or three seconds with Claude and up to ten with
  Codex. The pill says *Polishing with Claude…*; a click on it types the
  words as said instead. If the agent is missing, not signed in, slower
  than 30 seconds or refuses, the basic text is typed and the pill says so.
- In a terminal or code editor (Ghostty, kitty, Alacritty, foot, WezTerm,
  Konsole, GNOME Terminal, VS Code, VSCodium, Cursor, Zed, JetBrains IDEs,
  Neovide, Emacs, Kate, Sublime Text…, by the focused window's class), the
  words are typed as heard unless **Leave terminals and code editors
  alone** is off. Corrections still apply.

A tidied dictation leaves the pill on screen for a moment with **Copy
original**, which puts the words as heard (with corrections) on the
clipboard.

## History

Every typed dictation is kept in
`$XDG_STATE_HOME/cybexos/dictation/history.json` (mode 0600): the text that
was typed, the words as heard, the app it went to, the tidy-up used and
whether it was typed or copied. Nothing leaves this computer.

The history opens from the menubar's dictation action (middle click),
**Super+Ctrl+Shift+X**, Settings and the pill. It lists the dictations by
day, newest first, with a search field. Each one can be typed again into the
window underneath (the panel closes first), copied, corrected, deleted, and,
with a recording, played (`pw-play`) or transcribed again with the current
speech model (`voxtype transcribe`). Escape or a click elsewhere closes it.

Words that could not be typed (no virtual keyboard and no clipboard) are
kept even with Don't save, until you type them again or delete them; the
pill offers **Open history**. Expired entries and their recordings are
removed the next time the history is read or written.

With **Keep recordings**, each dictation's audio (16 kHz 16-bit mono WAV,
about 2 MB a minute) is moved to `recordings/ID.wav` beside it; otherwise
it is deleted as soon as the words are typed.

## How it works

The shell starts each dictation as `voxtype record start --file=PATH` with
`PATH` in `$XDG_RUNTIME_DIR/cybexos-dictation/`. Voxtype streams it through
its sliding-window engine, re-reading the recording as it grows; nothing is
typed while you speak. Cybex OS patches Voxtype
(`nix/packages/voxtype-dictation.patch`) to:

- write the running text (committed words plus the current guess) to
  `PATH.live`, which the pill shows;
- publish a streamed transcript's outcome in `PATH.done`, as Voxtype already
  does for one transcribed after recording, so the shell knows it is
  complete;
- treat a comma-separated `whisper.language` string as the list of languages
  to detect between, as `voxtype config set whisper.language en,nl` writes it;
- keep a live dictation's audio when a pass of the model takes longer than
  the 0.8-second re-read interval. Upstream holds about 0.6 seconds of audio
  for the streaming engine and drops the rest while a pass runs, and after
  stop drained that backlog one chunk per pass, minutes on a slow machine.
  The patch holds over a minute and takes in all queued audio before the
  next pass, so the final words are complete and arrive one pass after stop;
- send the final pass over the whole recording as the transcript of a
  session that types nothing as it goes (a new `Whole` event), while the
  recording fits the 29-second window. Streamed words are committed once
  and cannot be taken back, so a live guess ("Iceland?") could otherwise
  survive into the typed text; with it, the typed words are the same as a
  transcription after recording. Longer dictations keep the streamed text;
- stream a batch Parakeet model (the multilingual TDT v3 family, which has
  no cache-aware streaming graph) through the same sliding window as
  Whisper when `parakeet.streaming` is on. Upstream streams only its
  English-only `parakeet-unified` model;
- write the session's audio to `PATH.wav` (16-bit mono WAV, written
  atomically before the outcome) for every file-output recording, streamed
  or not.

When `PATH.done` reports the words, `scripts/dictation.py deliver` applies
the corrections and tidy-up, types them with `wtype`, and records the
dictation in the history, keeping or deleting `PATH.wav`. It reports each
step to the shell as a JSON line (`tidying`, `typing` with the text, then
`result`). Where no virtual keyboard is available the words are copied to
the clipboard instead, with a notification. A `PATH.original` file, which
a click on the pill creates while tidy-up runs, makes it type the words as
heard. Voxtype's state file
(`$XDG_RUNTIME_DIR/voxtype/state`) keeps the menubar's microphone action
honest for every recording, including ones the shell did not start.

Silence produces nothing (Voxtype's energy voice detection), instead of
Whisper's invented "Thank you."

### Configuration

Settings owns these keys in `~/.config/voxtype/config.toml` and keeps them in
line with what it shows, through `voxtype config set` (comments and every
other key are kept):

| Key | Value |
| --- | --- |
| `engine` | `parakeet` for Fast & accurate, otherwise `whisper` |
| `parakeet.model`, `parakeet.streaming`, `parakeet.on_demand_loading` | `parakeet-tdt-0.6b-v3-int8` and live text, set (before `engine`) only once Parakeet is downloaded and chosen, then left alone |
| `whisper.model` | `base`, or `ggml-large-v3-turbo-q8_0.bin` once downloaded |
| `whisper.language` | `en`, or `en,nl` with a second language |
| `whisper.streaming` | live text |
| `whisper.on_demand_loading` | the opposite of live text: streaming needs the model loaded |
| `streaming.revision_mode` | live text; the shell's recordings go to a file, so a revised guess only edits text in memory |
| `whisper.initial_prompt` | the vocabulary, or unset |

The daemon restarts when one of them changes, never during a dictation. A
fresh account starts from `desktop/defaults/voxtype.toml`. The rest of the
file (microphone, length limit, voice detection) is yours.

### The downloadable models

`scripts/dictation.py download enhanced` fetches
`ggml-large-v3-turbo-q8_0.bin` from a pinned revision of
[ggerganov/whisper.cpp on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp)
(874,188,075 bytes, SHA-256
`317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1`) into
`~/.local/share/voxtype/models/`. `download parakeet` fetches the four files
of the 8-bit ONNX export of NVIDIA's
[Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
(CC BY 4.0) from revision `8f23f0c0` of
[istupakov/parakeet-tdt-0.6b-v3-onnx](https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx)
into `~/.local/share/voxtype/models/parakeet-tdt-0.6b-v3-int8/`
(670,480,039 bytes in all; each file's length and SHA-256 are pinned in the
helper). ONNX Runtime comes from Nixpkgs with the Voxtype build
(`onnxSupport`).

Each download checks the free space first and writes each file to a hidden
`.part` file that is renamed into place only when its length and SHA-256
match, so Voxtype never loads a partial or altered file. An interrupted
download resumes (files already in place are kept); **Cancel download**
deletes the partial files. Settings names a model in `config.toml` only once
all its files are installed.

With live text on, the loaded model takes about 1 GB of memory (graphics
memory where Vulkan is available); the built-in model about 200 MB.

### Speed and processors

Voxtype runs Whisper on the GPU through Vulkan, and on the CPU where no
Vulkan device is found. whisper.cpp turns its vector instructions off in any
build that sets `SOURCE_DATE_EPOCH`, as every Nix build does, so Cybex OS
turns them back on (`GGML_SSE42`, `GGML_AVX`, `GGML_AVX2`, `GGML_FMA`,
`GGML_F16C`, `GGML_BMI2` in `nix/modules/default.nix`). Dictation therefore
needs an x86-64 processor with AVX2, FMA, F16C and BMI2: Intel from 2013
(Haswell) and AMD from 2015 (Excavator) on. On an older one the voxtype unit
does not start (`ConditionCPUFeature`), and the menubar, the shortcuts'
pill and the assistant's push-to-talk do not offer dictation; the rest of
the desktop is unaffected.

On the development host (64 cores, no GPU used), a 6-second sentence took:

| Model | Without the vector instructions, 8 threads | Shipped (AVX2), 8 threads |
| --- | --- | --- |
| Built in (`base`) | 8.1 s | 5.4 s |
| Accurate (`large-v3-turbo`, 8-bit) | 23.3 s | 10.1 s |
| Fast & accurate (Parakeet v3, 8-bit, ONNX Runtime on the CPU) | — | 1.3 s |

(the whole `voxtype transcribe` command, model loading included). On the
CPU, live words lag a few seconds behind you and the enhanced model takes
seconds per sentence; a GPU is much faster. On that sentence ("The weather
is nice today") the built-in model wrote "But where is ice today?" and the
enhanced model got it right. Parakeet wrote it exactly, and the Dutch
sentence ("Goedemorgen. Dit is een test van het dicteren…") but for one
word ("verticeren").

## Scripts

`cybexos-runtime ipc dictation FUNCTION` drives dictation as the shortcut
and Settings do: `toggle`, `start`, `stop`, `cancel`, `status` (JSON),
`language CODE|off`, `model base|large-v3-turbo|parakeet`,
`liveText true|false`, `tidy off|basic|polish`, `addCorrection HEARD WRITE`,
`removeCorrection HEARD`, `keepRecordings true|false`, `offer`,
`dismissOffer`, `refreshModel`, `history`, `closeHistory` and `settings`
(opens the page above).

`scripts/dictation.py history list|clear|delete ID|edit ID TEXT|type ID|copy
ID|play ID|retranscribe ID|forget HEARD WRITE` is what the history panel
runs.

## Validation

`checks.x86_64-linux.dictation` boots the desktop in a VM and dictates
through F9, the real Voxtype daemon and PipeWire, with espeak-ng speech
played into a null sink as the microphone: live words in the pill, typing
into a focused terminal that keeps its focus, the history entry it leaves,
the first-use offer (recommending Parakeet for English), the history panel
from its shortcut, a correction, Polish falling back to basic tidy-up
without an agent, a kept recording, live text off, a second language written
to `config.toml`, the enhanced model and Parakeet (installed as a finished
download leaves them; there is no network) chosen, loaded, and recognising
an English and a Dutch sentence with one key, Parakeet with live words.
`tests/nixos/test_dictation_helper.py` covers the downloads' integrity,
resume, cancellation and space checks, the configuration it writes (the
Parakeet section before the engine), corrections, tidy-up, the Polish
commands and their limits, delivery to code windows, the history's
retention, edits and suggestions, recordings and the clipboard fallback.
Polish against a real Claude Code and Codex account was tried by hand.
None of it qualifies a physical microphone, a GPU, or recognition quality on
real voices.
