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
has_remotes=0
if [[ -n "$remotes" ]]; then
  has_remotes=1
fi

# Prune remotes if any exist
if [[ "$has_remotes" -eq 1 ]]; then
  if ! git fetch --prune --all; then
    die "Failed to fetch remotes; aborting to avoid deleting with stale refs"
  fi
fi

# Determine default branch (prefer remote HEAD, else init.defaultBranch, else main/master)
base_name=""
base_ref=""
base_ref_is_remote=0
default_remote=""

if printf '%s\n' "$remotes" | grep -qx 'origin'; then
  default_remote="origin"
else
  default_remote="$(printf '%s\n' "$remotes" | head -n1 || true)"
fi

resolve_ref() {
  local name="$1"
  local prefer_remote="${2:-0}"
  if [[ "$prefer_remote" -eq 1 && -n "$default_remote" ]] && git show-ref --verify --quiet "refs/remotes/$default_remote/$name"; then
    base_name="$name"
    base_ref="$default_remote/$name"
    base_ref_is_remote=1
    return 0
  fi
  if git show-ref --verify --quiet "refs/heads/$name"; then
    base_name="$name"
    base_ref="$name"
    base_ref_is_remote=0
    return 0
  fi
  if [[ -n "$default_remote" ]] && git show-ref --verify --quiet "refs/remotes/$default_remote/$name"; then
    base_name="$name"
    base_ref="$default_remote/$name"
    base_ref_is_remote=1
    return 0
  fi
  return 1
}

if [[ -n "$default_remote" ]]; then
  if remote_head=$(git symbolic-ref -q "refs/remotes/$default_remote/HEAD" 2>/dev/null); then
    resolve_ref "${remote_head#refs/remotes/$default_remote/}" "$has_remotes" || true
  fi
fi

if [[ -z "$base_ref" ]]; then
  default_branch="$(git config --get init.defaultBranch || true)"
  if [[ -n "$default_branch" ]]; then
    resolve_ref "$default_branch" "$has_remotes" || true
  fi
fi

if [[ -z "$base_ref" ]]; then
  for candidate in main master; do
    resolve_ref "$candidate" "$has_remotes" && break
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

remote_default_ref=""
if [[ "$has_remotes" -eq 1 && -n "$default_remote" && -n "$base_name" ]]; then
  if git show-ref --verify --quiet "refs/remotes/$default_remote/$base_name"; then
    remote_default_ref="$default_remote/$base_name"
  fi
fi

to_delete=()
skipped=0
for b in "${merged[@]}"; do
  tip="$(git rev-parse --verify "refs/heads/$b" 2>/dev/null || true)"
  if [[ -z "$tip" ]]; then
    echo "Skipping $b (failed to resolve branch tip)." >&2
    skipped=1
    continue
  fi
  if [[ "$has_remotes" -eq 1 ]]; then
    if [[ -n "$remote_default_ref" ]]; then
      if ! git merge-base --is-ancestor "$tip" "$remote_default_ref" 2>/dev/null; then
        echo "Skipping $b (not merged into $remote_default_ref)." >&2
        skipped=1
        continue
      fi
    else
      contains_remote="$(git branch -r --contains "$tip" 2>/dev/null || true)"
      if [[ -z "$contains_remote" ]]; then
        echo "Skipping $b (not contained in any remote branch)." >&2
        skipped=1
        continue
      fi
    fi
  fi
  to_delete+=("$b")
done

if [[ ${#to_delete[@]} -eq 0 ]]; then
  echo "No branches eligible for deletion."
  exit 0
fi

for b in "${to_delete[@]}"; do
  if ! git branch -d -- "$b"; then
    echo "Skipping $b (not fully merged or in use)." >&2
    skipped=1
  fi
done

if [[ "$skipped" -eq 1 ]]; then
  echo "Done (some branches were skipped)." >&2
  exit 0
fi

echo "Done."
