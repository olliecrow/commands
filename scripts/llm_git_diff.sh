#!/bin/bash
# Save as: llm_git_diff.sh
# Usage:
#   ./llm_git_diff.sh /path/to/repo
#   ./llm_git_diff.sh /path/to/repo --staged
#   ./llm_git_diff.sh /path/to/repo -- path/inside/repo
#   ./llm_git_diff.sh /path/to/repo <any other git diff args>
#
# Options (script-specific):
#   --save-path <file>      Save diff to the given path
#   --save-path=<file>      (alias form)
#   --save_path ...         (underscore alias)
#   --include-untracked     Include untracked files (respects .gitignore)
#   --include_untracked     (underscore alias)
#
# Notes:
#   - Script-specific options must appear before a standalone `--` separator.

set -euo pipefail

# ---------------------------
# config / constants
# ---------------------------
readonly TMP_BASENAME="gitdiff_clip"
readonly DIFF_CMD=("git" "--no-pager" "diff")

# ---------------------------
# helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

# ---------------------------
# validate environment
# ---------------------------
need_cmd git
need_cmd osascript

# ---------------------------
# parse args
# ---------------------------
[[ $# -ge 1 ]] || die "usage: $(basename "$0") <repo_dir_or_subdir> [--save-path <file>] [git-diff-args...]"

REPO_PATH="$1"; shift || true
[[ -d "$REPO_PATH" ]] || die "Not a directory: $REPO_PATH"

# Resolve to absolute path to avoid surprises
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# Ensure we're inside a Git work tree (accepts subdirs inside the repo)
if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not a Git repository (or inside one): $REPO_PATH"
fi

# Track temporary intent-to-add and clean up on exit
ADDED_INTENT=0
UNTRACKED=()
cleanup_intent() {
  if [[ "${ADDED_INTENT}" -eq 1 && ${#UNTRACKED[@]} -gt 0 ]]; then
    git -C "$REPO_PATH" reset -q -- "${UNTRACKED[@]}" || true
  fi
}
trap cleanup_intent EXIT

#############################
# parse script-specific args
#############################
SAVE_PATH=""
DIFF_ARGS=()
INCLUDE_UNTRACKED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --save-path|--save_path)
      [[ $# -ge 2 ]] || die "--save-path requires a file path"
      SAVE_PATH="$2"
      shift 2
      ;;
    --save-path=*|--save_path=*)
      SAVE_PATH="${1#*=}"
      shift
      ;;
    --include-untracked|--include_untracked)
      INCLUDE_UNTRACKED=1
      shift
      ;;
    --)
      # pass the rest (including --) straight to git diff
      DIFF_ARGS+=("$@")
      break
      ;;
    *)
      DIFF_ARGS+=("$1")
      shift
      ;;
  esac
done

# Extract any pathspec provided to forward to ls-files when including untracked
PATHSPEC_ARGS=()
sep=0
for a in "${DIFF_ARGS[@]}"; do
  if [[ $sep -eq 1 ]]; then
    PATHSPEC_ARGS+=("$a")
  elif [[ "$a" == "--" ]]; then
    sep=1
  fi
done

# ---------------------------
# produce diff file target
# ---------------------------
CLEANUP_ON_FAIL=0
if [[ -n "$SAVE_PATH" ]]; then
  save_dir="$(dirname "$SAVE_PATH")"
  mkdir -p "$save_dir" || die "Failed to create directory: $save_dir"
  # Normalize to absolute path for clipboard AppleScript reliability
  SAVE_PATH="$(cd "$save_dir" && pwd)/$(basename "$SAVE_PATH")"
  TXT_FILE="$SAVE_PATH"
else
  # mktemp with .txt extension (create then append suffix for portability)
  TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX")"
  TXT_FILE="${TMP_FILE}.txt"
  mv "$TMP_FILE" "$TXT_FILE"
  CLEANUP_ON_FAIL=1
fi

# If requested, temporarily include untracked files via intent-to-add
if [[ "$INCLUDE_UNTRACKED" -eq 1 ]]; then
  if [[ ${#PATHSPEC_ARGS[@]} -gt 0 ]]; then
    # Limit to provided pathspec
    readarray -d '' -t UNTRACKED < <(git -C "$REPO_PATH" ls-files --others --exclude-standard -z -- "${PATHSPEC_ARGS[@]}") || true
  else
    readarray -d '' -t UNTRACKED < <(git -C "$REPO_PATH" ls-files --others --exclude-standard -z) || true
  fi
  if [[ ${#UNTRACKED[@]} -gt 0 ]]; then
    git -C "$REPO_PATH" add -N -- "${UNTRACKED[@]}"
    ADDED_INTENT=1
  fi
fi

# Run the diff; pass through any extra args provided
# Examples you can pass:
#   --staged
#   -- name/of/file
#   COMMITA..COMMITB -- path/inside/repo
("${DIFF_CMD[@]}" -C "$REPO_PATH" "${DIFF_ARGS[@]}" > "$TXT_FILE") || {
  if [[ "$CLEANUP_ON_FAIL" -eq 1 ]]; then rm -f "$TXT_FILE"; fi
  die "git diff failed"
}

if [[ -n "$SAVE_PATH" ]]; then
  echo "Saved diff to: $TXT_FILE"
fi

# ---------------------------
# put the FILE on macOS clipboard
# ---------------------------
# Note: The file must persist until you've pasted it.
if osascript - "$TXT_FILE" <<'APPLESCRIPT'
on run argv
  set p to POSIX file (item 1 of argv)
  set the clipboard to p
end run
APPLESCRIPT
then
  lines=$(wc -l <"$TXT_FILE" | tr -d ' ')
  bytes=$(wc -c <"$TXT_FILE" | tr -d ' ')
  echo "Placed file on clipboard:"
  echo "  $TXT_FILE  (${lines} lines, ${bytes} bytes)"
  echo "Note: keep this file until after you paste."
else
  if [[ "$CLEANUP_ON_FAIL" -eq 1 ]]; then rm -f "$TXT_FILE"; fi
  die "Failed to place file on clipboard"
fi
