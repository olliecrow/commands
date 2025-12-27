#!/usr/bin/env bash
set -euo pipefail

# Prune stale remote-tracking refs and delete local branches merged into default.

die() { echo "Error: $*" >&2; exit 1; }

if [[ $# -ne 0 ]]; then
  die "usage: $(basename "$0")"
fi

# Ensure we're in a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository"

# Prune remotes if any exist
if [[ -n "$(git remote)" ]]; then
  git fetch --prune --all
fi

# Determine default branch (prefer remote HEAD, else main/master)
base_name=""
base_ref=""
default_remote=""

if git remote | grep -qx 'origin'; then
  default_remote="origin"
else
  default_remote="$(git remote | head -n1 || true)"
fi

if [[ -n "$default_remote" ]]; then
  if remote_head=$(git symbolic-ref -q "refs/remotes/$default_remote/HEAD" 2>/dev/null); then
    base_name="${remote_head#refs/remotes/$default_remote/}"
    if git show-ref --verify --quiet "refs/heads/$base_name"; then
      base_ref="$base_name"
    elif git show-ref --verify --quiet "refs/remotes/$default_remote/$base_name"; then
      base_ref="$default_remote/$base_name"
    fi
  fi
fi

if [[ -z "$base_ref" ]]; then
  if git show-ref --verify --quiet refs/heads/main; then
    base_name="main"
    base_ref="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    base_name="master"
    base_ref="master"
  fi
fi

if [[ -z "$base_ref" ]]; then
  die "Could not determine default branch (origin/HEAD, main, or master)"
fi

current="$(git branch --show-current || true)"

merged=()
while IFS= read -r b; do
  [[ -z "$b" ]] && continue
  if [[ -n "$base_name" && "$b" == "$base_name" ]]; then
    continue
  fi
  if [[ -n "$current" && "$b" == "$current" ]]; then
    continue
  fi
  merged+=("$b")
done < <(git for-each-ref --merged "$base_ref" --format='%(refname:short)' refs/heads)

if [[ ${#merged[@]} -eq 0 ]]; then
  echo "No merged branches to delete."
  exit 0
fi

for b in "${merged[@]}"; do
  git branch -D "$b"
done

echo "Done."
