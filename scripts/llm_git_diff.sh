#!/bin/bash
# Save as: llm_git_diff.sh
# Usage:
#   ./llm_git_diff.sh /path/to/repo
#   ./llm_git_diff.sh /path/to/repo --staged
#   ./llm_git_diff.sh /path/to/repo -- path/inside/repo
#   ./llm_git_diff.sh /path/to/repo <any other git diff args>

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
[[ $# -ge 1 ]] || die "usage: $(basename "$0") <repo_dir_or_subdir> [git-diff-args...]"

REPO_PATH="$1"; shift || true
[[ -d "$REPO_PATH" ]] || die "Not a directory: $REPO_PATH"

# Resolve to absolute path to avoid surprises
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# Ensure we're inside a Git work tree (accepts subdirs inside the repo)
if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not a Git repository (or inside one): $REPO_PATH"
fi

# ---------------------------
# produce diff file
# ---------------------------
# mktemp with .txt extension (create then append suffix for portability)
TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX")"
TXT_FILE="${TMP_FILE}.txt"
mv "$TMP_FILE" "$TXT_FILE"

# Run the diff; pass through any extra args provided
# Examples you can pass:
#   --staged
#   -- name/of/file
#   COMMITA..COMMITB -- path/inside/repo
("${DIFF_CMD[@]}" -C "$REPO_PATH" "$@" > "$TXT_FILE") || {
  rm -f "$TXT_FILE"
  die "git diff failed"
}

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
  rm -f "$TXT_FILE"
  die "Failed to place file on clipboard"
fi
