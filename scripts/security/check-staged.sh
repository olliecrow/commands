#!/usr/bin/env bash
# Check real staged content, including binary-marked files and paths.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
git diff --cached --text --no-ext-diff --no-textconv --no-color --unified=0 |
  awk '/^diff / { in_hunk = 0; next } /^@@ / { in_hunk = 1; next } in_hunk && /^\+/ { sub(/^\+/, ""); print }' >"$tmp"
git -c core.quotePath=false diff --cached --name-only >>"$tmp"
bash "$script_dir/check-sensitive-text.sh" --context=staged "$tmp"
