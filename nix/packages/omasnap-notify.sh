#!@bash@
# Omasnap's notifications on Cybex OS. Omasnap runs Omarchy's
# `omarchy-notification-send`; nix/packages/omasnap.nix installs this file
# under that name on Omasnap's own PATH only. It accepts the same command
# line and sends a standard notification:
#
#   [options] HEADLINE [DESCRIPTION] [--exec PROGRAM ARGS... |
#     --action LABEL PROGRAM WORDS... [--action ...] [--with ARGS...]]
#
# --exec is the card's click. Each --action is a button, the first also the
# click, and the --with arguments are appended to every action's command.
# A chosen command runs as its own words, never through a shell.
set -euo pipefail

headline=
description=
app_name=omasnap
urgency=low
icon=
image=
expire=-1
transient=0
exec_args=()
labels=()
# Every action's words, one after another: action N is action_count[N]
# words from action_start[N].
action_words=()
action_start=()
action_count=()
with_args=()

option() {
  case $1 in
    -g|--glyph|-r|--replace-id) ;;  # Omarchy's glyphs and ids; nothing here uses them
    -u|--urgency) urgency=$2 ;;
    --app-name) app_name=$2 ;;
    -i|--icon) icon=$2 ;;
    --image) image=$2 ;;
    -t|--expire-time) expire=$2 ;;
    *) return 1 ;;
  esac
}

value_option() {
  case $1 in
    -g|--glyph|-r|--replace-id|-u|--urgency|--app-name|-i|--icon|--image|-t|--expire-time) return 0 ;;
  esac
  return 1
}

flag() {
  case $1 in
    -p|--print-id) return 0 ;;
    --transient) transient=1; return 0 ;;
  esac
  return 1
}

while (($# > 0)); do
  if flag "$1"; then
    shift
  elif value_option "$1"; then
    (($# >= 2)) || { echo "Missing value for $1" >&2; exit 1; }
    option "$1" "$2"
    shift 2
  else
    break
  fi
done
(($# > 0)) || { echo "A notification needs a headline" >&2; exit 1; }
headline=$1
shift
if (($# > 0)) && [[ $1 != --exec && $1 != --action && $1 != --with ]] && ! value_option "$1" && ! flag "$1"; then
  description=$1
  shift
fi

while (($# > 0)); do
  case $1 in
    --exec)
      shift
      exec_args=("$@")
      break
      ;;
    --action)
      (($# >= 3)) || { echo "--action needs a label and a command" >&2; exit 1; }
      labels+=("$2")
      shift 2
      action_start+=("${#action_words[@]}")
      while (($# > 0)) && [[ $1 != --action && $1 != --with && $1 != --exec ]]; do
        action_words+=("$1")
        shift
      done
      action_count+=($((${#action_words[@]} - ${action_start[-1]})))
      ;;
    --with)
      shift
      with_args=("$@")
      break
      ;;
    *)
      if flag "$1"; then
        shift
      elif value_option "$1" && (($# >= 2)); then
        option "$1" "$2"
        shift 2
      else
        echo "Unknown option: $1" >&2
        exit 1
      fi
      ;;
  esac
done

case $urgency in low|normal|critical) ;; *) urgency=low ;; esac
[[ $expire =~ ^-?[0-9]+$ ]] || expire=-1

# Cards name their sender: Omasnap's are the desktop's screenshots.
[[ $app_name == omasnap ]] && app_name=Screenshot
arguments=(--app-name="$app_name" --urgency="$urgency" --expire-time="$expire")
# The capture is the card's picture, as the screenshot notifications were.
if [[ -n $image ]]; then
  arguments+=(--icon="$image")
elif [[ -n $icon ]]; then
  arguments+=(--icon="$icon")
fi
((transient)) && arguments+=(--transient)
if ((${#exec_args[@]} > 0)); then
  arguments+=(--action="default=Edit")
elif ((${#labels[@]} > 0)); then
  arguments+=(--action="default=${labels[0]}")
  for index in "${!labels[@]}"; do
    arguments+=(--action="$index=${labels[index]}")
  done
fi

if ((${#exec_args[@]} == 0 && ${#labels[@]} == 0)); then
  exec @notify-send@ "${arguments[@]}" -- "$headline" "$description"
fi

# notify-send waits while the card offers actions and prints the chosen one.
chosen=$(@notify-send@ "${arguments[@]}" -- "$headline" "$description") || exit 0
case $chosen in
  default)
    if ((${#exec_args[@]} > 0)); then
      exec "${exec_args[@]}"
    fi
    chosen=0
    ;;
  ''|*[!0-9]*) exit 0 ;;
esac
((chosen < ${#action_start[@]} && action_count[chosen] > 0)) || exit 0
exec "${action_words[@]:action_start[chosen]:action_count[chosen]}" "${with_args[@]}"
