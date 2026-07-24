#!/bin/bash
# Concatenate allowed files under a path and copy to clipboard.
# Default: copy the resulting .txt FILE to the macOS clipboard.
# Use --string to copy the plain TEXT content instead.
# Optionally use --save-path to write the bundle to a specific file path.
set -euo pipefail

# ---------------------------
# Constants / configuration
# ---------------------------
readonly ALLOWED_EXTENSIONS="txt md py json jsonl yaml yml js html sh rs toml cfg css ini rst c cc cpp h hpp cuh cu ts tsx jsx java rb go bat ps1 fish make cmake gradle"
readonly ALLOWED_FILENAMES="Dockerfile Containerfile Imagefile Makefile Procfile Rakefile Gemfile Pipfile Brewfile Jenkinsfile Vagrantfile LICENSE COPYING NOTICE README CHANGES CHANGELOG VERSION"
readonly HEADER_PREFIX="# File: "
readonly TMP_BASENAME="llm_bundle"
MODE="file"  # "file" (default) | "text"
IGNORE_GITIGNORE="false"

# ---------------------------
# Helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }

usage() {
  local exit_code="${1:-1}"
  local ext_list name_list output_fd
  name_list=""
  ext_list="$(echo "$ALLOWED_EXTENSIONS" | sed 's/ /, ./g' | sed 's/^/./')"
  output_fd=2
  if [[ "$exit_code" -eq 0 ]]; then
    output_fd=1
  fi
  if [[ -n "$ALLOWED_FILENAMES" ]]; then
    name_list="$(echo "$ALLOWED_FILENAMES" | tr ' ' ', ')"
  fi

  cat >&"$output_fd" <<USAGE
Usage: llm_copy.sh [--string] [--save-path <file>] <path> [path ...]

  --string   Copy the PLAIN TEXT content to the macOS clipboard (not a file).
  --save-path <file>
             Save the bundled output to the given path. In file mode, that
             file is also placed on the clipboard. In string mode, the text
             is copied to the clipboard and also written to the file.
  --ignore-gitignore
             Ignore .gitignore filtering when gathering files.

The tool gathers files with extensions: $ext_list${name_list:+ and filenames: $name_list}
USAGE
  exit "$exit_code"
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
  local display_path file_absolute
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

  if [[ -n "$SAVE_PATH" ]]; then
    file_absolute="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
    if [[ "$file_absolute" == "$SAVE_PATH" ]]; then
      return 0
    fi
  fi

  is_allowed_file "$file" || return 0
  {
    printf "%s%s\n" "$HEADER_PREFIX" "$rel_path"
    cat "$file"
    printf "\n"
  } >>"$TMP_FILE"
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
    --save-path)
      [[ $# -ge 2 ]] || die "--save-path requires a file path"
      SAVE_PATH="$2"
      shift 2
      ;;
    --save-path=*)
      SAVE_PATH="${1#*=}"
      shift
      ;;
    --ignore-gitignore)
      IGNORE_GITIGNORE="true"
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    --)
      shift
      paths+=("$@")
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

[[ ${#paths[@]} -lt 1 ]] && usage 1

# ---------------------------
# Validate environment
# ---------------------------
case "$MODE" in
  file) need_cmd osascript ;;
  text) need_cmd pbcopy ;;
  *) die "Invalid MODE: $MODE" ;;
esac

# Build into a temporary file. A requested save path is replaced only after the
# bundle is complete, so a failed run does not damage an existing file.
CLEANUP_BUILD_FILE=1
cleanup() {
  if [[ "$CLEANUP_BUILD_FILE" -eq 1 && -n "${BUILD_FILE:-}" ]]; then
    rm -f -- "$BUILD_FILE"
  fi
}
trap cleanup EXIT

if [[ -n "$SAVE_PATH" ]]; then
  save_dir="$(dirname "$SAVE_PATH")"
  mkdir -p "$save_dir" || die "Failed to create directory: $save_dir"
  SAVE_PATH="$(cd "$save_dir" && pwd)/$(basename "$SAVE_PATH")"
  BUILD_FILE="$(mktemp "$save_dir/.${TMP_BASENAME}.XXXXXX")"
  OUTPUT_FILE="$SAVE_PATH"
else
  if [[ "$MODE" == "file" ]]; then
    BUILD_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX").txt"
    OUTPUT_FILE="$BUILD_FILE"
  else
    BUILD_FILE="$(mktemp -t "${TMP_BASENAME}.XXXXXX")"
    OUTPUT_FILE="$BUILD_FILE"
  fi
fi
TMP_FILE="$BUILD_FILE"

# ---------------------------
# Build bundle
# ---------------------------
for TARGET_PATH in "${paths[@]}"; do
  if [[ -f "$TARGET_PATH" ]]; then
    ROOT="$(dirname "$TARGET_PATH")"
    base="$(basename "$TARGET_PATH")"

    # If respecting .gitignore (default), skip files ignored by git.
    if [[ "$IGNORE_GITIGNORE" != "true" ]] && has_git && is_in_git_repo "$ROOT"; then
      if git -C "$ROOT" check-ignore -q -- "$base"; then
        # Ignored by git; skip.
        continue
      fi
    fi

    rel="${TARGET_PATH#"$ROOT"/}"
    process_file "$TARGET_PATH" "$rel"

  elif [[ -d "$TARGET_PATH" ]]; then
    TARGET_ABS="$(cd "$TARGET_PATH" && pwd)"
    if [[ "$IGNORE_GITIGNORE" != "true" ]] && has_git && is_in_git_repo "$TARGET_ABS"; then
      # Use git to enumerate only files that aren't ignored.
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
        rel="${file#"$TARGET_PATH"/}"
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
  if [[ -n "$SAVE_PATH" ]]; then
    mv -f -- "$BUILD_FILE" "$OUTPUT_FILE"
    CLEANUP_BUILD_FILE=0
    TMP_FILE="$OUTPUT_FILE"
  elif [[ "$MODE" == "file" ]]; then
    CLEANUP_BUILD_FILE=0
  fi

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
      if [[ -z "$SAVE_PATH" ]]; then
        rm -f -- "$TMP_FILE"
      fi
      die "Failed to place file on clipboard"
    fi
  fi
else
  ext_list="$(echo "$ALLOWED_EXTENSIONS" | sed 's/ /, ./g' | sed 's/^/./')"
  if [[ -n "$ALLOWED_FILENAMES" ]]; then
    name_list=" and filenames: $(echo "$ALLOWED_FILENAMES" | tr ' ' ', ')"
  else
    name_list=""
  fi
  echo "No supported files found ($ext_list$name_list)"
fi
