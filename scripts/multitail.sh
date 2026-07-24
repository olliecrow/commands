#!/bin/bash
# Follow every regular file inside a directory, spawning tail sessions as needed.

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

Continuously tails every regular file within the required directory argument.
New files are picked up automatically. Use -h/--help to show this message.
USAGE
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

watched_files=()
tail_processes=()

cleanup() {
  local process_id
  for process_id in "${tail_processes[@]}"; do
    kill "$process_id" >/dev/null 2>&1 || true
  done
  wait "${tail_processes[@]}" 2>/dev/null || true
}

is_watched() {
  local candidate="$1"
  local index
  for index in "${!watched_files[@]}"; do
    if [[ "${watched_files[$index]}" == "$candidate" ]] &&
      kill -0 "${tail_processes[$index]}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# ---------------------------
# main
# ---------------------------
main() {
  need_cmd tail

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

  shopt -s nullglob dotglob
  echo "Watching files in $log_dir (Ctrl+C to stop)"

  while :; do
    for file in "$log_dir"/*; do
      [[ -f "$file" ]] || continue
      if ! is_watched "$file"; then
        tail "${TAIL_ARGS[@]}" "$file" &
        watched_files+=("$file")
        tail_processes+=("$!")
      fi
    done
    sleep "$POLL_INTERVAL"
  done
}

main "$@"
