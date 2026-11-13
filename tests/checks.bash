# Runs independent checks side by side. Source it, name each check with
# `check NAME COMMAND...`, then call `run_checks TITLE`.
#
# Each check keeps its output to itself and prints it whole when it ends. A
# failing check's output is held back and printed last, above the summary.
# Every check runs to the end, also after another one failed. run_checks
# returns 1 when a check failed.
#
#   CYBEXOS_TESTS_RUN_JOBS=N   checks at a time (default: the CPU count)

if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 501)); then
  echo "The checks need bash 5.1 or newer (the dev shell has it: nix develop)" >&2
  exit 2
fi

jobs=${CYBEXOS_TESTS_RUN_JOBS:-}
if [[ ! $jobs =~ ^[1-9][0-9]*$ ]]; then
  jobs=$(nproc 2>/dev/null) || jobs=4
fi

names=() commands=()
check() {
  names+=("$1")
  shift
  commands+=("$(printf '%q ' "$@")")
}

run_checks() {
  local title=$1 index
  work=$(mktemp -d "${TMPDIR:-/tmp}/cybexos-tests-run.XXXXXX") || exit 2
  # Ends the checks and what they started, when this run is told to stop.
  stop() {
    trap - INT TERM
    local pids=() job
    descendants() {
      local child
      for child in $(pgrep -P "$1" 2>/dev/null); do
        descendants "$child"
        pids+=("$child")
      done
    }
    descendants "$$"
    for job in $(jobs -p); do pids+=("$job"); done
    ((${#pids[@]})) && kill "${pids[@]}" 2>/dev/null
    wait
    rm -rf -- "$work"
    exit 130
  }
  trap 'rm -rf -- "$work"' EXIT
  trap stop INT TERM

  now() { local time=${EPOCHREALTIME/[.,]/}; printf '%s' "$((time / 1000))"; }
  seconds() { printf '%d.%d' "$(($1 / 1000))" "$(($1 % 1000 / 100))"; }
  rule() { printf '\n==== %s ====\n' "$1"; }

  declare -A index_of
  statuses=() started=() took=() failed=()
  running=0
  begun=$(now)

  launch() {
    local index=$1
    started[index]=$(now)
    (eval "${commands[index]}") >"$work/$index.out" 2>&1 </dev/null &
    index_of[$!]=$index
    running=$((running + 1))
  }

  # Waits for one check to end and reports it.
  collect() {
    local pid status index
    wait -n -p pid
    status=$?
    [[ -n ${pid:-} ]] || return
    index=${index_of[$pid]}
    running=$((running - 1))
    statuses[index]=$status
    took[index]=$(($(now) - started[index]))
    if ((status == 0)); then
      rule "passed: ${names[index]} ($(seconds "${took[index]}")s)"
      cat -- "$work/$index.out"
    else
      failed+=("$index")
      rule "FAILED: ${names[index]} (exit $status, $(seconds "${took[index]}")s); its output follows at the end"
    fi
  }

  for index in "${!names[@]}"; do
    while ((running >= jobs)); do collect; done
    launch "$index"
  done
  while ((running > 0)); do collect; done

  for index in "${failed[@]}"; do
    rule "FAILED: ${names[index]} (exit ${statuses[index]}, $(seconds "${took[index]}")s)"
    printf '$ %s\n' "${commands[index]}"
    cat -- "$work/$index.out"
  done

  rule "$title: ${#names[@]} checks, $jobs at a time, $(seconds $(($(now) - begun)))s"
  echo "slowest:"
  for index in "${!names[@]}"; do
    printf '%s %s\n' "${took[index]}" "${names[index]}"
  done | sort -rn | head -n 5 | while read -r time name; do
    printf '  %6ss  %s\n' "$(seconds "$time")" "$name"
  done
  if ((${#failed[@]})); then
    echo "FAILED, ${#failed[@]} of ${#names[@]} checks:"
    for index in "${failed[@]}"; do
      printf '  %s (exit %s)\n' "${names[index]}" "${statuses[index]}"
    done
    return 1
  fi
  echo "all ${#names[@]} checks passed"
}
