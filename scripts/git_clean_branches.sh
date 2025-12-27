#!/usr/bin/env bash
set -euo pipefail

# Prune stale remote-tracking refs and delete local branches merged into default.

die() { echo "Error: $*" >&2; exit 1; }

if [[ $# -ne 0 ]]; then
  die "usage: $(basename "$0")"
fi

# Ensure we're in a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository"

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "No commits yet; nothing to clean."
  exit 0
fi

remotes="$(git remote)"

# Prune remotes if any exist
if [[ -n "$remotes" ]]; then
  if ! git fetch --prune --all; then
    echo "Warning: failed to fetch remotes; using local refs only." >&2
  fi
fi

# Determine default branch (prefer remote HEAD, else init.defaultBranch, else main/master)
base_name=""
base_ref=""
default_remote=""

if printf '%s\n' "$remotes" | grep -qx 'origin'; then
  default_remote="origin"
else
  default_remote="$(printf '%s\n' "$remotes" | head -n1 || true)"
fi

resolve_ref() {
  local name="$1"
  if git show-ref --verify --quiet "refs/heads/$name"; then
    base_name="$name"
    base_ref="$name"
    return 0
  fi
  if [[ -n "$default_remote" ]] && git show-ref --verify --quiet "refs/remotes/$default_remote/$name"; then
    base_name="$name"
    base_ref="$default_remote/$name"
    return 0
  fi
  return 1
}

if [[ -n "$default_remote" ]]; then
  if remote_head=$(git symbolic-ref -q "refs/remotes/$default_remote/HEAD" 2>/dev/null); then
    resolve_ref "${remote_head#refs/remotes/$default_remote/}" || true
  fi
fi

if [[ -z "$base_ref" ]]; then
  default_branch="$(git config --get init.defaultBranch || true)"
  if [[ -n "$default_branch" ]]; then
    resolve_ref "$default_branch" || true
  fi
fi

if [[ -z "$base_ref" ]]; then
  for candidate in main master; do
    resolve_ref "$candidate" && break
  done
fi

if [[ -z "$base_ref" ]]; then
  die "Could not determine default branch (origin/HEAD, init.defaultBranch, main, or master)"
fi

current="$(git branch --show-current 2>/dev/null || git symbolic-ref -q --short HEAD 2>/dev/null || true)"
in_use_list=""
while IFS= read -r line; do
  case "$line" in
    branch\ refs/heads/*)
      in_use_list+="${line#branch refs/heads/}"$'\n'
      ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null || true)

merged=()
while IFS= read -r b; do
  [[ -z "$b" ]] && continue
  if [[ -n "$base_name" && "$b" == "$base_name" ]]; then
    continue
  fi
  if [[ -n "$current" && "$b" == "$current" ]]; then
    continue
  fi
  if [[ -n "$in_use_list" ]] && printf '%s' "$in_use_list" | grep -Fxq -- "$b"; then
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
