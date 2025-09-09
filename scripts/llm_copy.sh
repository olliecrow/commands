#!/bin/bash
# Concatenate allowed files under a path and copy to clipboard.
# Default: copy TEXT content. With --file, put the resulting .txt FILE on the clipboard (macOS).
set -euo pipefail

# ---------------------------
# Constants / configuration
# ---------------------------
readonly ALLOWED_EXTENSIONS="txt md py json jsonl yaml yml js html sh rs"
readonly HEADER_PREFIX="# File: "
readonly TMP_BASENAME="llm_bundle"
MODE="text"  # "text" | "file"

# ---------------------------
# Helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<USAGE
Usage: llm [--file] <path> [path ...]

  --file     Place the resulting .txt file ITSELF on the macOS clipboard (not plain text).
                Note: the file must remain on disk until you've pasted it.

The tool gathers files with extensions: $(echo $ALLOWED_EXTENSIONS | sed 's/ /, ./g' | sed 's/^/./')
USAGE
  exit 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

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
    --file)
      MODE="file"
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
  text) need_cmd pbcopy ;;
  file) need_cmd osascript ;;
  *) die "Invalid MODE: $MODE" ;;
esac

# Create temp file (.txt when --file so the paste target sees a text file)
if [[ "$MODE" == "file" ]]; then
  TMP_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX").txt"
  # Do NOT auto-delete in --file mode; user needs the file to persist for paste.
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
    rel="${TARGET_PATH#$ROOT/}"
    process_file "$TARGET_PATH" "$rel"
  elif [[ -d "$TARGET_PATH" ]]; then
    ROOT="$TARGET_PATH"
    # Exclude hidden directories (starting with .) at any depth
    while IFS= read -r -d '' file; do
      rel="${file#$ROOT/}"
      # If any path component (directory) starts with '.', skip
      if [[ "$rel" =~ (^|/)\.[^/]+ ]]; then
        continue
      fi
      process_file "$file" "$rel"
    done < <(find "$TARGET_PATH" -type f -print0 | sort -z)
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