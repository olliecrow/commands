#!/usr/bin/env bash
set -euo pipefail

# One-file-per-commit script.
# - Unstages current staging (no changes discarded)
# - Commits each changed item (tracked/untracked, including deletions)
# - Handles renames/copies as a single commit
# - Expands untracked dirs and skips empty commits
# - Message: "Updated: {filename}."

# Ensure we're in a git repo
git rev-parse --is-inside-work-tree >/dev/null

# Unstage everything currently staged, keep working tree intact
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  git reset
fi

# Read NUL-delimited porcelain records safely (handles spaces/newlines in filenames)
while IFS= read -r -d '' rec; do
  code="${rec:0:2}"
  rest="${rec:3}"

  # Skip submodules (optional safeguard); remove this if you want them included
  # if [[ "$code" == "SM" ]]; then continue; fi

  if [[ "$code" == *R* || "$code" == *C* ]]; then
    # Rename/Copy lines include two NUL-terminated paths under -z.
    old="$rest"
    if ! IFS= read -r -d '' new; then
      echo "Error: expected rename/copy destination for '$old'." >&2
      exit 1
    fi

    # Stage both sides so the rename is captured in a single commit
    git add -A -- "$old" "$new"
    if ! git diff --cached --quiet; then
      git commit -m "Updated: $new."
    fi
  else
    p="$rest"

    # Stage deletion if it no longer exists; otherwise stage the file (works for untracked too)
    if [[ ! -e "$p" ]]; then
      # Only attempt rm if it was tracked; ignore if it wasn't
      git rm -f -- "$p" >/dev/null 2>&1 || true
    else
      git add -- "$p"
    fi

    if ! git diff --cached --quiet; then
      git commit -m "Updated: $p."
    fi
  fi
done < <(git status --porcelain -z -uall)

echo "Done."
