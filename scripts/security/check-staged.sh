#!/usr/bin/env bash
# Check real staged content, including binary-marked files and paths.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
# The scanner keeps added-line locations from the patch before scanning.
git -c core.quotePath=true diff --cached --no-renames --src-prefix=a/ --dst-prefix=b/ \
  --text --no-ext-diff --no-textconv --no-color --unified=0 >"$tmp"
bash "$script_dir/check-sensitive-text.sh" --context=staged --patch "$tmp"
git -c core.quotePath=false diff --cached --name-only >"$tmp"
bash "$script_dir/check-sensitive-text.sh" --context=staged-paths "$tmp"
