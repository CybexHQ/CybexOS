# Dictation

Press **F9** (or **Super+Ctrl+X**, or the microphone mute key) and speak.
A pill at the bottom of the screen shows your words as you say them. Press
the key again to stop: the finished words are typed into the window you were
using, which keeps its focus the whole time. A click on the pill also stops
it. The menubar's microphone action does the same.

Dictation comes with the developer tooling feature
(`cybexos.features.developer`, default on). Speech is recognised on this
computer by [Voxtype](https://github.com/peteonrails/voxtype) with OpenAI's
Whisper models; no audio leaves it. The assistant's push-to-talk (Super+I)
uses the same daemon and settings ([assistant.md](assistant.md)).

## First use

The first dictation works straight away with the small Whisper model built
into every installation (`base`, 142 MB, in `/etc/cybexos/models`). Once it
has typed its words, a card appears where the pill was:

- **Make dictation more accurate** offers the enhanced model, Whisper
  large-v3-turbo (834 MB download). It recognises names, technical words
  and languages other than English much better, and also runs locally.
- **Do you also dictate in another language?** English is the default.
  Choosing a second language makes Whisper decide, each time, which of your
  two languages you are speaking. One key covers both.

**Not now** keeps the built-in model. The card appears once; everything on it
is also in **Settings → Bar & Control Center → Indicators → Dictation**. It
never takes the keyboard until you click it, so it cannot catch words meant
for your window.

## Settings

**Settings → Bar & Control Center → Indicators → Dictation**:

- **Language** and **Second language** (or None).
- **Speech model**: Standard (built in) or Enhanced. Choosing Enhanced
  before it is downloaded starts the download; the row shows its progress,
  and **Remove enhanced model** deletes it again (dictation returns to the
  built-in model first).
- **Live text**: words in the pill while you speak (default on). It keeps the
  speech model loaded so the words can follow you; off, the model loads when
  a dictation starts and is released afterwards, and the words arrive when
  you stop.
- **Vocabulary**: names and terms, separated by commas, that Whisper should
  expect (its initial prompt).

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
  transcription after recording. Longer dictations keep the streamed text.

When `PATH.done` reports the words, `scripts/dictation.py type` types them
with `wtype`. Where no virtual keyboard is available they are copied to the
clipboard instead, with a notification. Voxtype's state file
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
| `whisper.model` | `base`, or `ggml-large-v3-turbo-q8_0.bin` once downloaded |
| `whisper.language` | `en`, or `en,nl` with a second language |
| `whisper.streaming` | live text |
| `whisper.on_demand_loading` | the opposite of live text: streaming needs the model loaded |
| `streaming.revision_mode` | live text; the shell's recordings go to a file, so a revised guess only edits text in memory |
| `whisper.initial_prompt` | the vocabulary, or unset |

The daemon restarts when one of them changes, never during a dictation. A
fresh account starts from `desktop/defaults/voxtype.toml`. The rest of the
file (microphone, length limit, voice detection) is yours.

### The enhanced model

`scripts/dictation.py download` fetches
`ggml-large-v3-turbo-q8_0.bin` from a pinned revision of
[ggerganov/whisper.cpp on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp)
(874,188,075 bytes, SHA-256
`317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1`) into
`~/.local/share/voxtype/models/`. It checks the free space first and writes
to a hidden `.part` file that is renamed into place only when its length and
SHA-256 match, so Voxtype never loads a partial or altered file. An
interrupted download resumes; **Cancel download** deletes the partial file.
Settings names the model in `config.toml` only once it is installed.

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
| Enhanced (`large-v3-turbo`, 8-bit) | 23.3 s | 10.1 s |

(the whole `voxtype transcribe` command, model loading included). On the
CPU, live words lag a few seconds behind you and the enhanced model takes
seconds per sentence; a GPU is much faster. On that sentence ("The weather
is nice today") the built-in model wrote "But where is ice today?" and the
enhanced model got it right.

## Scripts

`cybexos-runtime ipc dictation FUNCTION` drives dictation as the shortcut
and Settings do: `toggle`, `start`, `stop`, `cancel`, `status` (JSON),
`language CODE|off`, `model base|large-v3-turbo`, `liveText true|false`,
`offer`, `dismissOffer`, `refreshModel` and `settings` (opens the page above).

## Validation

`checks.x86_64-linux.dictation` boots the desktop in a VM and dictates
through F9, the real Voxtype daemon and PipeWire, with espeak-ng speech
played into a null sink as the microphone: live words in the pill, typing
into a focused terminal that keeps its focus, the first-use offer, live text
off, a second language written to `config.toml`, and the enhanced model
(installed as a finished download leaves it; there is no network) chosen,
loaded, and recognising an English and a Dutch sentence with one key.
`tests/nixos/test_dictation_helper.py` covers the download's integrity,
resume, cancellation and space checks, the configuration it writes and the
clipboard fallback. Neither qualifies a physical microphone, a GPU, or
recognition quality on real voices.
