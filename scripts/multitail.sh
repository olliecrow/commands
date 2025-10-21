#!/bin/bash
# Follow every .log file inside a directory, spawning tail sessions as needed.

set -euo pipefail

# ---------------------------
# config / constants
# ---------------------------
readonly POLL_INTERVAL=1
readonly TAIL_ARGS=(-n0 -F)

# ---------------------------
# helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: multitail <directory>

Continuously tails every .log file within the required directory argument. New
log files are picked up automatically. Use -h/--help to show this message.
USAGE
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

escape_pattern() {
  # Escape regex chars so pgrep matches the full tail command safely.
  printf '%s' "$1" | sed -e 's/[][^$.|?*+(){}\\]/\\&/g'
}

cleanup() {
  pkill -P $$ tail >/dev/null 2>&1 || true
}

# ---------------------------
# main
# ---------------------------
main() {
  need_cmd tail
  need_cmd pgrep
  need_cmd pkill

  if [[ $# -eq 1 ]]; then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
    esac
  fi

  if [[ $# -ne 1 ]]; then
    usage >&2
    die "directory argument required"
  fi

  local log_dir="$1"

  if [[ ! -d "$log_dir" ]]; then
    die "directory not found: $log_dir"
  fi

  trap cleanup EXIT
  trap 'cleanup; exit 130' INT TERM

  shopt -s nullglob
  echo "Watching $log_dir for *.log files (Ctrl+C to stop)"

  while :; do
    for file in "$log_dir"/*.log; do
      local pattern
      pattern="tail -n0 -F $(escape_pattern "$file")"
      if ! pgrep -f "$pattern" >/dev/null 2>&1; then
        tail "${TAIL_ARGS[@]}" "$file" &
      fi
    done
    sleep "$POLL_INTERVAL"
  done
}

main "$@"
