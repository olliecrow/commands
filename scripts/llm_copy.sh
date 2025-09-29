#!/bin/bash
# Concatenate allowed files under a path and copy to clipboard.
# Default: copy the resulting .txt FILE to the macOS clipboard.
# Use --string to copy the plain TEXT content instead.
# Optionally use --save-path to write the bundle to a specific file path.
set -euo pipefail

# ---------------------------
# Constants / configuration
# ---------------------------
readonly ALLOWED_EXTENSIONS="txt md py json jsonl yaml yml js html sh rs toml cfg css ini env rst c cc cpp h hpp cuh cu ts tsx jsx java rb go bat ps1 fish make cmake gradle"
readonly ALLOWED_FILENAMES="Dockerfile Containerfile Imagefile Makefile Procfile Rakefile Gemfile Pipfile Brewfile Jenkinsfile Vagrantfile LICENSE COPYING NOTICE README CHANGES CHANGELOG VERSION ENV"
readonly HEADER_PREFIX="# File: "
readonly TMP_BASENAME="llm_bundle"
MODE="file"  # "file" (default) | "text"

# ---------------------------
# Helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }

usage() {
  local ext_list name_list
  name_list=""
  ext_list="$(echo "$ALLOWED_EXTENSIONS" | sed 's/ /, ./g' | sed 's/^/./')"
  if [[ -n "$ALLOWED_FILENAMES" ]]; then
    name_list="$(echo "$ALLOWED_FILENAMES" | tr ' ' ', ')"
  fi

  cat >&2 <<USAGE
Usage: llm_convert.sh [--string] [--save-path <file>] <path> [path ...]

  --string   Copy the PLAIN TEXT content to the macOS clipboard (not a file).
  --save-path <file>
             Save the bundled output to the given path. In file mode, that
             file is also placed on the clipboard. In string mode, the text
             is copied to the clipboard and also written to the file.

The tool gathers files with extensions: $ext_list${name_list:+ and filenames: $name_list}
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

is_allowed_file() {
  local file="$1" base ext
  base="${file##*/}"
  ext="${base##*.}"

  if [[ "$base" == "$ext" ]]; then
    [[ -n "$ALLOWED_FILENAMES" ]] && echo "$ALLOWED_FILENAMES" | tr ' ' '\n' | grep -Fxq "$base"
  else
    echo "$ALLOWED_EXTENSIONS" | grep -qw "$ext"
  fi
}

process_file() {
  local file="$1" rel_path="$2"
  local display_path
  display_path="${rel_path:-$file}"

  if [[ ! -e "$file" ]]; then
    echo "Warning: '$display_path' no longer exists; skipping" >&2
    return 0
  fi

  if [[ ! -f "$file" ]]; then
    # Skip anything that resolved to a directory or special file.
    echo "Warning: '$display_path' is not a regular file; skipping" >&2
    return 0
  fi

  if [[ ! -r "$file" ]]; then
    echo "Warning: '$display_path' is not readable; skipping" >&2
    return 0
  fi

  is_allowed_file "$file" || return 0
  printf "%s%s\n" "$HEADER_PREFIX" "$rel_path" >>"$TMP_FILE"
  cat "$file" >>"$TMP_FILE"
  printf "\n" >>"$TMP_FILE"
}

# ---------------------------
# Parse args
# ---------------------------
paths=()
SAVE_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --string)
      MODE="text"
      shift
      ;;
    --save-path|--save_path)
      [[ $# -ge 2 ]] || die "--save-path requires a file path"
      SAVE_PATH="$2"
      shift 2
      ;;
    --save-path=*|--save_path=*)
      SAVE_PATH="${1#*=}"
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

# Choose output file path.
# In file mode, use .txt suffix for temp so paste targets see a text file.
if [[ -n "$SAVE_PATH" ]]; then
  save_dir="$(dirname "$SAVE_PATH")"
  mkdir -p "$save_dir" || die "Failed to create directory: $save_dir"
  # Normalize to absolute path
  SAVE_PATH="$(cd "$save_dir" && pwd)/$(basename "$SAVE_PATH")"
  TMP_FILE="$SAVE_PATH"
  # Never auto-delete a user-specified file.
  trap ':' EXIT
else
  if [[ "$MODE" == "file" ]]; then
    TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX").txt"
    # Do NOT auto-delete in file mode; user needs the file to persist for paste.
    trap ':' EXIT
  else
    TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX")"
    # Auto-delete temp in text mode only when not saving to a specific path.
    trap 'rm -f "$TMP_FILE"' EXIT
  fi
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
    TARGET_ABS="$(cd "$TARGET_PATH" && pwd)"
    if has_git && is_in_git_repo "$TARGET_ABS"; then
      # Use git to enumerate non-ignored files under TARGET_PATH.
      while IFS= read -r -d '' git_rel; do
        file_abs="$TARGET_ABS/$git_rel"

        # Mirror previous 'find -type f' behavior by skipping symlinks.
        [[ -L "$file_abs" ]] && continue

        # Compute path relative to the user-specified TARGET_PATH for the header and hidden-dir filter.
        rel="$git_rel"

        # Preserve existing behavior: skip any path that has a hidden directory component (.^)
        if [[ "$rel" =~ (^|/)\.[^/]+ ]]; then
          continue
        fi

        process_file "$file_abs" "$rel"
      done < <(git -C "$TARGET_ABS" ls-files -z --cached --others --exclude-standard -- . | sort -z)
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
  if [[ -n "$SAVE_PATH" ]]; then
    echo "Saved bundle to: $TMP_FILE ($total_lines lines, $total_bytes bytes)"
  fi
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
      # Only delete the file if it was a temporary one we created.
      if [[ -z "$SAVE_PATH" ]]; then rm -f "$TMP_FILE"; fi
      die "Failed to place file on clipboard"
    fi
  fi
else
  # Nothing gathered
  if [[ "$MODE" == "file" && -z "$SAVE_PATH" ]]; then rm -f "$TMP_FILE"; fi
  ext_list="$(echo "$ALLOWED_EXTENSIONS" | sed 's/ /, ./g' | sed 's/^/./')"
  if [[ -n "$ALLOWED_FILENAMES" ]]; then
    name_list=" and filenames: $(echo "$ALLOWED_FILENAMES" | tr ' ' ', ')"
  else
    name_list=""
  fi
  echo "No supported files found ($ext_list$name_list)"
fi
