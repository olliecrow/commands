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
# Keep content patterns in sync with scripts/security/check-sensitive-text.sh.
readonly SECRET_ASSIGNMENT_REGEX='([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss]([Ww][Oo][Rr][Dd]|[Ww][Dd])|[Ss][Ee][Cc][Rr][Ee][Tt]([_-]?([Aa][Cc][Cc][Ee][Ss][Ss][_-]?)?[Kk][Ee][Yy])?|[Pp][Rr][Ii][Vv][Aa][Tt][Ee][_-]?[Kk][Ee][Yy])["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_./+=-]{4,}[0-9+/=][A-Za-z0-9_./+=-]{4,}(["'"'"'`,;)}[:space:]]|$)'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/security/token-pattern.sh
source "$script_dir/security/token-pattern.sh"
readonly PRIVATE_KEY_REGEX='-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY-----'
readonly HEADER_PREFIX="# File: "
readonly TMP_BASENAME="llm_bundle"
MODE="file"  # "file" (default) | "text"
IGNORE_GITIGNORE="false"
ALLOW_SENSITIVE="false"

# ---------------------------
# Helpers
# ---------------------------
die() { echo "Error: $*" >&2; exit 1; }

allowed_inputs_text() {
  printf 'extensions: .%s and filenames: %s' \
    "${ALLOWED_EXTENSIONS// /, .}" "${ALLOWED_FILENAMES// /, }"
}

usage() {
  local exit_code="${1:-1}"
  local output_fd=2
  if [[ "$exit_code" -eq 0 ]]; then
    output_fd=1
  fi

  cat >&"$output_fd" <<USAGE
Usage: llm_copy.sh [--string] [--save-path <file>] [--allow-sensitive] <path> [path ...]

  --string   Copy the PLAIN TEXT content to the macOS clipboard (not a file).
  --save-path <file>
             Save the bundled output to the given path. In file mode, that
             file is also placed on the clipboard. In string mode, the text
             is copied to the clipboard and also written to the file. If the
             clipboard tool is missing, the file is still saved.
  --ignore-gitignore
             Ignore .gitignore filtering when gathering files.
  --allow-sensitive
             Include secret-like filenames and content. Without it, those
             files are skipped and named in a warning. The rest are copied.

The tool gathers files with $(allowed_inputs_text).
Paths with a hidden component (a name that starts with ".") are skipped.
Secret-like names are skipped (case-insensitive): *secret*, *credential*,
*.pem, *.key, id_rsa*, id_ed25519*, id_ecdsa*, id_dsa*, .env*, aws.ini.
A file whose content matches a credential is skipped and named. The rest
of the bundle is still written. --allow-sensitive includes both.
USAGE
  exit "$exit_code"
}

has_git() { command -v git >/dev/null 2>&1; }

# Returns 0 if PATH is inside a git work tree; otherwise 1.
is_in_git_repo() {
  local p="$1" dir
  if [[ -d "$p" ]]; then dir="$p"; else dir="$(dirname "$p")"; fi
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Match whole words in the space-separated lists without starting a process
# per file. A name with no dot uses the filename list only.
is_allowed_file() {
  local file="$1" base ext
  base="${file##*/}"
  ext="${base##*.}"

  if [[ "$base" == "$ext" ]]; then
    [[ "$base" != *" "* ]] && [[ " $ALLOWED_FILENAMES " == *" $base "* ]]
  else
    [[ -n "$ext" && "$ext" != *" "* ]] && [[ " $ALLOWED_EXTENSIONS " == *" $ext "* ]]
  fi
}

# Match secret-like names without regard to case and without a subprocess.
is_secret_name() {
  local status=1
  shopt -s nocasematch
  case "$1" in
    *secret*|*credential*|*.pem|*.key|id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*|.env*|aws.ini) status=0 ;;
  esac
  shopt -u nocasematch
  return "$status"
}

# True if any path component starts with ".".
has_hidden_component() {
  [[ "/$1" == */.* ]]
}

# Sort NUL-separated names. macOS sort has no -z, so each name is put on
# one line ("%" becomes %25 and newline becomes %0A), sorted, and restored.
# This encoding avoids backslashes, which bash 3.2 and bash 5 treat
# differently in a ${name//pattern/replacement} replacement.
sort_nul() {
  local percent='%' newline=$'\n' name
  while IFS= read -r -d '' name; do
    [[ -n "$name" ]] || continue
    name=${name//"$percent"/${percent}25}
    name=${name//"$newline"/${percent}0A}
    printf '%s\n' "$name"
  done | LC_ALL=C sort | while IFS= read -r name; do
    name=${name//"$percent"0A/$newline}
    name=${name//"$percent"25/$percent}
    printf '%s\0' "$name"
  done
}

# Create an empty file named <random>.txt in the temp directory.
make_temp_txt() {
  local tmp_root="${TMPDIR:-/tmp}" raw
  raw="$(mktemp "${tmp_root%/}/${TMP_BASENAME}.XXXXXX")" || return 1
  mv -- "$raw" "$raw.txt" || { rm -f -- "$raw"; return 1; }
  printf '%s\n' "$raw.txt"
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

  # Skip the output file itself. Compare names first to avoid a subshell
  # per file.
  if [[ -n "$SAVE_PATH" && "${file##*/}" == "${SAVE_PATH##*/}" ]]; then
    file_absolute="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
    if [[ "$file_absolute" == "$SAVE_PATH" ]]; then
      return 0
    fi
  fi

  is_allowed_file "$file" || return 0
  if [[ "$ALLOW_SENSITIVE" != "true" ]] && is_secret_name "${file##*/}"; then
    echo "warning: skipping $display_path (looks like a secrets file)" >&2
    return 0
  fi
  included_abs+=("$file")
  included_rel+=("$rel_path")
  write_file_section "$file" "$rel_path"
}

write_file_section() {
  local file="$1" rel_path="$2"
  {
    printf "%s%s\n" "$HEADER_PREFIX" "$rel_path"
    cat "$file"
    printf "\n"
  } >>"$TMP_FILE"
}

# Same normalization as the push scanner. One pass over the bundle, not
# one process per file. Line breaks stay put.
normalize_bytes() {
  LC_ALL=C tr -d '\000' <"$1" | LC_ALL=C tr -c '\11\12\40-\176' '?' >"$2"
}

# Return 0 when the bundle text matches a credential pattern, 1 when it
# does not, and 2 when the scan itself fails.
bundle_has_sensitive_content() {
  local status=0
  grep -aqE -e "$KNOWN_TOKEN_REGEX" -e "$SECRET_ASSIGNMENT_REGEX" -e "$PRIVATE_KEY_REGEX" -- "$1" || status=$?
  if [[ "$status" -gt 1 ]]; then
    return 2
  fi
  [[ "$status" -eq 0 ]]
}

# Print the bundle paths whose content matched. Names only, never values.
sensitive_paths_in_bundle() {
  grep -anE -e "^${HEADER_PREFIX}" -e "$KNOWN_TOKEN_REGEX" -e "$SECRET_ASSIGNMENT_REGEX" -e "$PRIVATE_KEY_REGEX" -- "$1" |
    awk -v prefix="$HEADER_PREFIX" '{
      sub(/^[0-9]+:/, "")
      if (index($0, prefix) == 1) {
        current = substr($0, length(prefix) + 1)
        next
      }
      if (current != "" && current != last) {
        print current
        last = current
      }
    }'
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
    --allow-sensitive)
      ALLOW_SENSITIVE="true"
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
  file) CLIPBOARD_CMD="osascript" ;;
  text) CLIPBOARD_CMD="pbcopy" ;;
  *) die "Invalid MODE: $MODE" ;;
esac
if ! command -v "$CLIPBOARD_CMD" >/dev/null 2>&1; then
  [[ -n "$SAVE_PATH" ]] ||
    die "Required command not found: $CLIPBOARD_CMD (use --save-path to save a file instead)"
  CLIPBOARD_CMD=""
fi

# Build into a temporary file. A requested save path is replaced only after the
# bundle is complete, so a failed run does not damage an existing file.
CLEANUP_BUILD_FILE=1
HITS_FILE=""
SCAN_FILE=""
cleanup() {
  if [[ "$CLEANUP_BUILD_FILE" -eq 1 && -n "${BUILD_FILE:-}" ]]; then
    rm -f -- "$BUILD_FILE"
  fi
  if [[ -n "${HITS_FILE:-}" ]]; then
    rm -f -- "$HITS_FILE"
  fi
  if [[ -n "${SCAN_FILE:-}" ]]; then
    rm -f -- "$SCAN_FILE"
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
  BUILD_FILE="$(make_temp_txt)" || die "Failed to create a temporary file"
  OUTPUT_FILE="$BUILD_FILE"
fi
TMP_FILE="$BUILD_FILE"

# ---------------------------
# Build bundle
# ---------------------------
included_abs=()
included_rel=()
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

        has_hidden_component "$rel" && continue

        process_file "$file_abs" "$rel"
      done < <(git -C "$TARGET_ABS" ls-files -z --cached --others --exclude-standard -- . | sort_nul)
    else
      # Fallback to original behavior when not in a repo or git isn't available.
      while IFS= read -r -d '' file; do
        rel="${file#"$TARGET_PATH"/}"
        has_hidden_component "$rel" && continue
        process_file "$file" "$rel"
      done < <(find "$TARGET_PATH" -type f -print0 | sort_nul)
    fi
  else
    echo "Warning: '$TARGET_PATH' does not exist or is not a file/directory" >&2
  fi
done

# ---------------------------
# Skip credential-like content
# ---------------------------
# Drop only the files that matched. If a match cannot be removed, keep the
# previous output and stop. Values are never printed.
if [[ "$ALLOW_SENSITIVE" != "true" && -s "$TMP_FILE" ]]; then
  SCAN_FILE="$(mktemp "${TMPDIR:-/tmp}/${TMP_BASENAME}.scan.XXXXXX")"
  normalize_bytes "$TMP_FILE" "$SCAN_FILE"
  sensitive_status=0
  bundle_has_sensitive_content "$SCAN_FILE" || sensitive_status=$?
  if [[ "$sensitive_status" -eq 0 ]]; then
    HITS_FILE="$(mktemp "${TMPDIR:-/tmp}/${TMP_BASENAME}.hits.XXXXXX")"
    sensitive_paths_in_bundle "$SCAN_FILE" >"$HITS_FILE"
    if [[ ! -s "$HITS_FILE" ]]; then
      die "credential-like content was found, but the file could not be named; nothing was copied or saved"
    fi
    while IFS= read -r sensitive_rel || [[ -n "${sensitive_rel:-}" ]]; do
      [[ -n "$sensitive_rel" ]] || continue
      echo "warning: skipping $sensitive_rel (credential-like content)" >&2
    done <"$HITS_FILE"
    : >"$TMP_FILE"
    included_index=0
    while [[ "$included_index" -lt ${#included_rel[@]} ]]; do
      if ! grep -Fxq -- "${included_rel[$included_index]}" "$HITS_FILE"; then
        write_file_section "${included_abs[$included_index]}" "${included_rel[$included_index]}"
      fi
      included_index=$((included_index + 1))
    done
    if [[ -s "$TMP_FILE" ]]; then
      normalize_bytes "$TMP_FILE" "$SCAN_FILE"
      sensitive_status=0
      bundle_has_sensitive_content "$SCAN_FILE" || sensitive_status=$?
      if [[ "$sensitive_status" -eq 0 ]]; then
        die "credential-like content remained after skipping files; nothing was copied or saved"
      elif [[ "$sensitive_status" -gt 1 ]]; then
        die "unable to scan the bundle for credential-like content"
      fi
    fi
  elif [[ "$sensitive_status" -gt 1 ]]; then
    die "unable to scan the bundle for credential-like content"
  fi
fi

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

  total_lines="$(wc -l <"$TMP_FILE" | tr -d '[:space:]')"
  total_bytes="$(wc -c <"$TMP_FILE" | tr -d '[:space:]')"
  if [[ -n "$SAVE_PATH" ]]; then
    echo "Saved bundle to: $TMP_FILE ($total_lines lines, $total_bytes bytes)"
  fi
  if [[ -z "$CLIPBOARD_CMD" ]]; then
    echo "warning: clipboard tool not found; file was saved only" >&2
  elif [[ "$MODE" == "text" ]]; then
    if pbcopy <"$TMP_FILE"; then
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
  echo "No supported files found ($(allowed_inputs_text))"
fi
