#!/bin/bash
# Concatenate allowed files under a path and copy to clipboard.
# Default: copy the resulting .txt FILE to the macOS clipboard.
# Use --string to copy the plain TEXT content instead.
set -euo pipefail

# ---------------------------
# Constants / configuration
# ---------------------------
readonly ALLOWED_EXTENSIONS="txt md py json jsonl yaml yml js html sh rs toml cfg css ini env rst c cc cpp h hpp cuh cu ts tsx jsx java rb go bat ps1 fish make cmake gradle"
readonly HEADER_PREFIX="# File: "
readonly TMP_BASENAME="llm_bundle"
MODE="file"  # "file" (default) | "text"

# ---------------------------
# Helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<USAGE
Usage: llm_convert.sh [--string] <path> [path ...]

  --string   Copy the PLAIN TEXT content to the macOS clipboard (not a file).

The tool gathers files with extensions: $(echo $ALLOWED_EXTENSIONS | sed 's/ /, ./g' | sed 's/^/./')
USAGE
  exit 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

has_git() { command -v git >/dev/null 2>&1; }

# Returns 0 if PATH is inside a git work tree; otherwise 1.
is_in_git_repo() {
  local p="$1" dir
  if [[ -d "$p" ]]; then dir="$p"; else dir="$(dirname "$p")"; fi
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Echoes the repo toplevel for PATH (or empty on failure).
git_toplevel_for() {
  local p="$1" dir
  if [[ -d "$p" ]]; then dir="$p"; else dir="$(dirname "$p")"; fi
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
}

is_allowed_ext() {
  local file="$1" ext
  ext="${file##*.}"
  [[ "$file" != "$ext" ]] && echo "$ALLOWED_EXTENSIONS" | grep -qw "$ext"
}

process_file() {
  local file="$1" rel_path="$2"
  is_allowed_ext "$file" || return 0
  printf "%s%s\n" "$HEADER_PREFIX" "$rel_path" >>"$TMP_FILE"
  cat "$file" >>"$TMP_FILE"
  printf "\n" >>"$TMP_FILE"
}

# ---------------------------
# Parse args
# ---------------------------
paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --string)
      MODE="text"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

[[ ${#paths[@]} -lt 1 ]] && usage

# ---------------------------
# Validate environment
# ---------------------------
case "$MODE" in
  file) need_cmd osascript ;;
  text) need_cmd pbcopy ;;
  *) die "Invalid MODE: $MODE" ;;
esac

# Create temp file (.txt when in file mode so the paste target sees a text file)
if [[ "$MODE" == "file" ]]; then
  TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX").txt"
  # Do NOT auto-delete in file mode; user needs the file to persist for paste.
  trap ':' EXIT
else
  TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX")"
  trap 'rm -f "$TMP_FILE"' EXIT
fi

# ---------------------------
# Build bundle
# ---------------------------
for TARGET_PATH in "${paths[@]}"; do
  if [[ -f "$TARGET_PATH" ]]; then
    ROOT="$(dirname "$TARGET_PATH")"
    base="$(basename "$TARGET_PATH")"

    # If in a git repo, skip file when .gitignore says to ignore it.
    if has_git && is_in_git_repo "$ROOT"; then
      if git -C "$ROOT" check-ignore -q -- "$base"; then
        # Ignored by git; skip.
        continue
      fi
    fi

    rel="${TARGET_PATH#$ROOT/}"
    process_file "$TARGET_PATH" "$rel"

  elif [[ -d "$TARGET_PATH" ]]; then
    if has_git && is_in_git_repo "$TARGET_PATH"; then
      # Use git to enumerate non-ignored files under TARGET_PATH.
      REPO_ROOT="$(git_toplevel_for "$TARGET_PATH")"
      # List tracked + untracked but not ignored, within this sub-tree.
      while IFS= read -r -d '' git_rel; do
        file_abs="$REPO_ROOT/$git_rel"

        # Mirror previous 'find -type f' behavior by skipping symlinks.
        [[ -L "$file_abs" ]] && continue

        # Compute path relative to the user-specified TARGET_PATH for the header and hidden-dir filter.
        rel="${file_abs#$TARGET_PATH/}"

        # Preserve existing behavior: skip any path that has a hidden directory component (.^)
        if [[ "$rel" =~ (^|/)\.[^/]+ ]]; then
          continue
        fi

        process_file "$file_abs" "$rel"
      done < <(git -C "$TARGET_PATH" ls-files -z --cached --others --exclude-standard -- . | sort -z)
    else
      # Fallback to original behavior when not in a repo or git isn't available.
      while IFS= read -r -d '' file; do
        rel="${file#$TARGET_PATH/}"
        # Skip any path whose component starts with '.'
        if [[ "$rel" =~ (^|/)\.[^/]+ ]]; then
          continue
        fi
        process_file "$file" "$rel"
      done < <(find "$TARGET_PATH" -type f -print0 | sort -z)
    fi
  else
    echo "Warning: '$TARGET_PATH' does not exist or is not a file/directory" >&2
  fi
done

# ---------------------------
# Copy to clipboard
# ---------------------------
if [[ -s "$TMP_FILE" ]]; then
  total_lines=$(wc -l <"$TMP_FILE")
  total_bytes=$(wc -c <"$TMP_FILE")
  if [[ "$MODE" == "text" ]]; then
    # Stream contents to clipboard
    if cat "$TMP_FILE" | pbcopy; then
      echo "Content copied to clipboard ($total_lines lines, $total_bytes bytes)"
    else
      die "Failed to copy content to clipboard"
    fi
  else
    # Put the FILE object on the clipboard (macOS). The file must persist.
    if osascript - "$TMP_FILE" <<'APPLESCRIPT'
on run argv
  set p to POSIX file (item 1 of argv)
  set the clipboard to p
end run
APPLESCRIPT
    then
      echo "Placed file on clipboard: $TMP_FILE ($total_lines lines, $total_bytes bytes)"
      echo "Note: keep this file until you've pasted it."
    else
      rm -f "$TMP_FILE"
      die "Failed to place file on clipboard"
    fi
  fi
else
  # Nothing gathered
  if [[ "$MODE" == "file" ]]; then rm -f "$TMP_FILE"; fi
  echo "No supported files found ($(echo $ALLOWED_EXTENSIONS | sed 's/ /, ./g' | sed 's/^/./') )"
fi
