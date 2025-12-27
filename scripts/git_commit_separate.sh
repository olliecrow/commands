#!/usr/bin/env bash
set -euo pipefail

# One-file-per-commit script.
# - Unstages anything currently staged (does NOT discard changes)
# - Commits each changed item one-by-one (tracked + untracked, including deletions)
# - Supports renames (stages old+new together as one commit)
# - Message: "Updated: {filename}."

# Ensure we're in a git repo
git rev-parse --is-inside-work-tree >/dev/null

# Unstage everything currently staged, keep working tree intact
git reset

# Read NUL-delimited porcelain records safely (handles spaces/newlines in filenames)
while IFS= read -r -d '' rec; do
  code="${rec:0:2}"
  rest="${rec:3}"

  # Skip submodules (optional safeguard); remove this if you want them included
  # if [[ "$code" == "SM" ]]; then continue; fi

  if [[ "$code" == R* || "$code" == C* ]]; then
    # Rename/Copy line looks like: "old -> new"
    old="${rest%% -> *}"
    new="${rest##* -> }"

    # Stage both sides so the rename is captured in a single commit
    git add -A -- "$old" "$new"
    git commit -m "Updated: $new."
  else
    p="$rest"

    # Stage deletion if it no longer exists; otherwise stage the file (works for untracked too)
    if [[ ! -e "$p" ]]; then
      # Only attempt rm if it was tracked; ignore if it wasn't
      git rm -f -- "$p" >/dev/null 2>&1 || true
    else
      git add -- "$p"
    fi

    git commit -m "Updated: $p."
  fi
done < <(git status --porcelain -z)

echo "Done."
