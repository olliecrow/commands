#!/bin/bash
# Usage:
#   ./llm_git_diff.sh /path/to/repo
#   ./llm_git_diff.sh /path/to/repo --staged
#   ./llm_git_diff.sh /path/to/repo -- path/inside/repo
#   ./llm_git_diff.sh /path/to/repo <any other git diff args>
#
# Options (script-specific):
#   --save-path <file>      Save diff to the given path
#   --save-path=<file>      (alias form)
#   --exclude-untracked     Exclude untracked files (included by default)
#   --string                Copy the DIFF TEXT to the clipboard (not the file)
#
# Notes:
#   - Script-specific options must appear before a standalone `--` separator.

set -euo pipefail

# ---------------------------
# config / constants
# ---------------------------
readonly TMP_BASENAME="gitdiff_clip"

# ---------------------------
# helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
usage() {
  cat <<'USAGE'
Usage: llm_git_diff.sh <repo_dir_or_subdir> [options] [git-diff-args...]

Options:
  --save-path <file>      Save diff to the given file
  --save-path=<file>      Save diff to the given file
  --exclude-untracked     Exclude untracked files (included by default)
  --string                Copy plain diff text to clipboard instead of file
  -h, --help              Show this help text

Notes:
  Script-specific options must appear before a standalone '--' separator.
  If the clipboard tool is missing, --save-path still saves the file.
  External diff drivers, textconv, and clean filters are not run.
USAGE
}

# ---------------------------
# validate environment
# ---------------------------
need_cmd git

# ---------------------------
# parse args
# ---------------------------
if [[ $# -eq 1 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
fi

[[ $# -ge 1 ]] || die "usage: $(basename "$0") <repo_dir_or_subdir> [--save-path <file>] [--string] [git-diff-args...]"

REPO_PATH="$1"; shift || true
[[ -d "$REPO_PATH" ]] || die "Not a directory: $REPO_PATH"

# Resolve to absolute path to avoid surprises
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# Ensure we're inside a Git work tree (accepts subdirs inside the repo)
if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not a Git repository (or inside one): $REPO_PATH"
fi

# Disable clean/process filters for both index creation and worktree diffs.
# Query names only: filter commands can contain private data.
SAFE_GIT=(git -C "$REPO_PATH")
filter_names="$(git -C "$REPO_PATH" config --name-only --get-regexp '^filter\..*\.(clean|process|required)$')" || {
  status=$?
  [[ "$status" -eq 1 ]] || die "Unable to read filter configuration"
}
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if [[ "$name" == *.required ]]; then
    SAFE_GIT+=(-c "$name=false")
  else
    SAFE_GIT+=(-c "$name=")
  fi
done <<<"$filter_names"

# Keep temporary files and the temporary index out of the user's repository.
TEMP_INDEX_DIR=""
REMOVE_OUTPUT_ON_EXIT=0
cleanup() {
  if [[ -n "$TEMP_INDEX_DIR" ]]; then
    rm -rf -- "$TEMP_INDEX_DIR"
  fi
  if [[ "$REMOVE_OUTPUT_ON_EXIT" -eq 1 && -n "${TXT_FILE:-}" ]]; then
    rm -f -- "$TXT_FILE"
  fi
}
trap cleanup EXIT

#############################
# parse script-specific args
#############################
SAVE_PATH=""
DIFF_ARGS=()
INCLUDE_UNTRACKED=1
CLIPBOARD_TEXT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --save-path)
      [[ $# -ge 2 ]] || die "--save-path requires a file path"
      SAVE_PATH="$2"
      shift 2
      ;;
    --save-path=*)
      SAVE_PATH="${1#*=}"
      shift
      ;;
    --exclude-untracked)
      INCLUDE_UNTRACKED=0
      shift
      ;;
    --string)
      CLIPBOARD_TEXT=1
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

# Validate clipboard tooling now that we know the mode. With --save-path the
# file is still useful without a clipboard tool.
CLIPBOARD_CMD="osascript"
[[ "$CLIPBOARD_TEXT" -eq 1 ]] && CLIPBOARD_CMD="pbcopy"
if ! command -v "$CLIPBOARD_CMD" >/dev/null 2>&1; then
  [[ -n "$SAVE_PATH" ]] ||
    die "Required command not found: $CLIPBOARD_CMD (use --save-path to save a file instead)"
  CLIPBOARD_CMD=""
fi

# Extract any pathspec provided to forward to ls-files when handling untracked entries
PATHSPEC_ARGS=()
sep=0
STAGED_DIFF=0
for a in ${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"}; do
  if [[ $sep -eq 1 ]]; then
    PATHSPEC_ARGS+=("$a")
  elif [[ "$a" == "--" ]]; then
    sep=1
  elif [[ "$a" == "--staged" || "$a" == "--cached" ]]; then
    STAGED_DIFF=1
  fi
done

# ---------------------------
# Produce the diff in a temporary file. A requested save path is replaced only
# after Git finishes successfully.
# ---------------------------
REMOVE_OUTPUT_ON_EXIT=1
if [[ -n "$SAVE_PATH" ]]; then
  save_dir="$(dirname "$SAVE_PATH")"
  mkdir -p "$save_dir" || die "Failed to create directory: $save_dir"
  SAVE_PATH="$(cd "$save_dir" && pwd)/$(basename "$SAVE_PATH")"
  TXT_FILE="$(mktemp "$save_dir/.${TMP_BASENAME}.XXXXXX")"
else
  tmp_root="${TMPDIR:-/tmp}"
  TMP_FILE="$(mktemp "${tmp_root%/}/${TMP_BASENAME}.XXXXXX")"
  TXT_FILE="${TMP_FILE}.txt"
  mv -- "$TMP_FILE" "$TXT_FILE"
fi

# Use a copy of the Git index when including untracked files. This preserves the
# user's real staging state even if the command fails or is interrupted.
TEMP_INDEX_FILE=""
record_untracked() {
  local relative_path="$1"
  local absolute_path
  absolute_path="$(cd "$REPO_PATH/$(dirname "$relative_path")" && pwd)/$(basename "$relative_path")"
  if [[ "$absolute_path" == "$TXT_FILE" || (-n "$SAVE_PATH" && "$absolute_path" == "$SAVE_PATH") ]]; then
    return
  fi
  UNTRACKED+=("$relative_path")
}

if [[ "$INCLUDE_UNTRACKED" -eq 1 ]]; then
  UNTRACKED=()
  if [[ ${#PATHSPEC_ARGS[@]} -gt 0 ]]; then
    # Limit to provided pathspec; read NUL-delimited filenames in a portable way
    while IFS= read -r -d $'\0' f; do
      record_untracked "$f"
    done < <(git -C "$REPO_PATH" ls-files --others --exclude-standard -z -- "${PATHSPEC_ARGS[@]}")
  else
    while IFS= read -r -d $'\0' f; do
      record_untracked "$f"
    done < <(git -C "$REPO_PATH" ls-files --others --exclude-standard -z)
  fi
  if [[ ${#UNTRACKED[@]} -gt 0 ]]; then
    TEMP_INDEX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${TMP_BASENAME}_index.XXXXXX")"
    TEMP_INDEX_FILE="$TEMP_INDEX_DIR/index"
    real_git_dir="$(git -C "$REPO_PATH" rev-parse --absolute-git-dir)"
    if [[ -f "$real_git_dir/index" ]]; then
      cp -p "$real_git_dir/index" "$TEMP_INDEX_FILE"
    fi
    if [[ "$STAGED_DIFF" -eq 1 ]]; then
      for f in "${UNTRACKED[@]}"; do
        mode=100644
        if [[ -L "$REPO_PATH/$f" ]]; then
          # Preserve the symlink itself, including a trailing newline.
          link_target="$(readlink "$REPO_PATH/$f"; printf '.')"
          link_target="${link_target%.}"
          link_target="${link_target%$'\n'}"
          blob="$(printf '%s' "$link_target" | git -C "$REPO_PATH" hash-object -w --stdin)"
          mode=120000
        else
          [[ ! -x "$REPO_PATH/$f" ]] || mode=100755
          blob="$(git -C "$REPO_PATH" hash-object -w --no-filters -- "$f")"
        fi
        GIT_INDEX_FILE="$TEMP_INDEX_FILE" git -C "$REPO_PATH" update-index --add --cacheinfo "$mode" "$blob" "$f"
      done
    else
      # Intent-to-add preserves new-file diff semantics. All filters are disabled.
      GIT_INDEX_FILE="$TEMP_INDEX_FILE" "${SAFE_GIT[@]}" add -N -- "${UNTRACKED[@]}"
    fi
  fi
fi

SAFE_DIFF_ARGS=()
flags_added=0
for a in ${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"}; do
  if [[ "$a" == -- && "$flags_added" -eq 0 ]]; then
    SAFE_DIFF_ARGS+=(--no-ext-diff --no-textconv)
    flags_added=1
  fi
  SAFE_DIFF_ARGS+=("$a")
done
[[ "$flags_added" -eq 1 ]] || SAFE_DIFF_ARGS+=(--no-ext-diff --no-textconv)

# Run the diff; pass through any extra args provided
# Examples you can pass:
#   --staged
#   -- name/of/file
#   COMMITA..COMMITB -- path/inside/repo
if [[ -n "$TEMP_INDEX_FILE" ]]; then
  GIT_INDEX_FILE="$TEMP_INDEX_FILE" "${SAFE_GIT[@]}" --no-pager diff "${SAFE_DIFF_ARGS[@]}" >"$TXT_FILE" || {
    die "git diff failed"
  }
else
  "${SAFE_GIT[@]}" --no-pager diff "${SAFE_DIFF_ARGS[@]}" >"$TXT_FILE" || {
    die "git diff failed"
  }
fi

if [[ -n "$SAVE_PATH" ]]; then
  mv -f -- "$TXT_FILE" "$SAVE_PATH"
  TXT_FILE="$SAVE_PATH"
  REMOVE_OUTPUT_ON_EXIT=0
  echo "Saved diff to: $TXT_FILE"
fi

# ---------------------------
# put the FILE on macOS clipboard
# ---------------------------
# Note: The file must persist until you've pasted it.
lines="$(wc -l <"$TXT_FILE" | tr -d '[:space:]')"
bytes="$(wc -c <"$TXT_FILE" | tr -d '[:space:]')"
if [[ -z "$CLIPBOARD_CMD" ]]; then
  echo "warning: clipboard tool not found; file was saved only" >&2
elif [[ "$CLIPBOARD_TEXT" -eq 1 ]]; then
  if pbcopy <"$TXT_FILE"; then
    echo "Copied text to clipboard (${lines} lines, ${bytes} bytes)"
  else
    die "Failed to copy text to clipboard"
  fi
elif osascript - "$TXT_FILE" <<'APPLESCRIPT'
on run argv
  set p to POSIX file (item 1 of argv)
  set the clipboard to p
end run
APPLESCRIPT
then
  REMOVE_OUTPUT_ON_EXIT=0
  echo "Placed file on clipboard:"
  echo "  $TXT_FILE  (${lines} lines, ${bytes} bytes)"
  echo "Note: keep this file until after you paste."
else
  die "Failed to place file on clipboard"
fi
