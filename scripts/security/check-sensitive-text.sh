#!/usr/bin/env bash
set -euo pipefail

context="text"
if [[ "${1:-}" == --context=* ]]; then
  context="${1#--context=}"
  shift
fi

if [[ "$#" -lt 1 ]]; then
  echo "usage: check-sensitive-text.sh [--context=<label>] <file> [file...]" >&2
  exit 2
fi

local_path_regex='(/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|[A-Za-z]:\\+Users\\+[A-Za-z0-9._-]+)'
allowed_path_placeholder_regex='(/Users/(YOU|USER|username)|/home/(user|USER|username)|[A-Za-z]:\\+Users\\+(YOU|USER|USERNAME|username))'
secret_assignment_regex='([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt])[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_./+=-]{12,}'
known_token_regex='((ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})'

search_line_numbers() {
  local pattern="$1"
  local file_path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg --line-number --no-heading --color never -e "$pattern" "$file_path" |
      cut -d: -f1 || true
  else
    grep -nE "$pattern" "$file_path" |
      cut -d: -f1 || true
  fi
}

search_disallowed_path_line_numbers() {
  local file_path="$1"
  awk \
    -v local_path="$local_path_regex" \
    -v allowed_placeholder="$allowed_path_placeholder_regex" \
    '{
      scrubbed = $0
      gsub(allowed_placeholder, "", scrubbed)
      if (scrubbed ~ local_path) {
        print NR
      }
    }' "$file_path"
}

display_name() {
  local file_path="$1"
  case "$file_path" in
    /* | [A-Za-z]:[\\/]*)
      basename "$file_path"
      ;;
    *)
      printf '%s\n' "$file_path"
      ;;
  esac
}

report_lines() {
  local label="$1"
  local line_numbers="$2"
  if [[ -n "$line_numbers" ]]; then
    printf '  %s on line(s): %s\n' "$label" "$(printf '%s\n' "$line_numbers" | paste -sd, -)" >&2
  fi
}

failed=0
for target in "$@"; do
  if [[ ! -f "$target" ]]; then
    continue
  fi

  path_matches="$(search_disallowed_path_line_numbers "$target")"

  secret_assignment_matches="$(search_line_numbers "$secret_assignment_regex" "$target")"
  known_token_matches="$(search_line_numbers "$known_token_regex" "$target")"

  if [[ -n "$path_matches" || -n "$secret_assignment_matches" || -n "$known_token_matches" ]]; then
    echo "policy violation in ${context}: $(display_name "$target")" >&2
    report_lines "local machine path" "$path_matches"
    report_lines "credential-like assignment" "$secret_assignment_matches"
    report_lines "known token format" "$known_token_matches"
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  cat >&2 <<'EOF'
Blocked by sensitive-text policy.
- Remove or redact secrets and credential-like values.
- Replace local absolute paths with repo-relative paths or placeholders like /path/to/project.
EOF
fi

exit "$failed"
