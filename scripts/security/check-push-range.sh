#!/usr/bin/env bash
# Scan commit messages and added lines in a push range for sensitive text.
# Any git failure or bad input exits non-zero, so an error never passes.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: check-push-range.sh [--from <sha>] --to <sha>

Scans every commit in <from>..<to>. Without --from, or with an all-zero
--from, scans all commits reachable from <to>. Merge commits are scanned
against their first parent. With no flags, reads the range that pre-commit sets for
pre-push hooks.
EOF
}

zero_ref="0000000000000000000000000000000000000000"
object_id_regex='^([0-9a-f]{40}|[0-9a-f]{64})$'
local_ref_regex='^(HEAD|refs/[A-Za-z0-9._/+-]+)$'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "error: $*" >&2
  exit 1
}

if [[ "$#" -eq 0 ]]; then
  from_ref="${PRE_COMMIT_FROM_REF:-}"
  to_ref="${PRE_COMMIT_TO_REF:-}"
  # pre-commit calls this for one ref only, and not at all when that ref is
  # already on the remote. A later ref in the same push, and an annotated
  # tag on an already pushed commit, are not scanned here. See the README.
  # pre-commit sets no range when the push includes the root commit.
  # It still names the local ref, so resolve that ref to a commit.
  local_ref="${PRE_COMMIT_LOCAL_BRANCH:-}"
  if [[ -z "$to_ref" && -n "$local_ref" ]]; then
    [[ "$local_ref" =~ $local_ref_regex ]] || die "invalid local ref for the push"
    to_ref="$(git rev-parse --verify --quiet "${local_ref}^{commit}")" ||
      die "unable to resolve the local ref for the push"
  fi
else
  from_ref=""
  to_ref=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --from | --to)
        [[ "$#" -ge 2 ]] || { usage; exit 2; }
        if [[ "$1" == "--from" ]]; then from_ref="$2"; else to_ref="$2"; fi
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage
        exit 2
        ;;
    esac
  done
fi

[[ -n "$to_ref" ]] || die "no push range given (expected --to or pre-commit refs)"
[[ "$to_ref" =~ $object_id_regex ]] || die "push target is not a full commit ID"
if [[ -n "$from_ref" ]]; then
  [[ "$from_ref" =~ $object_id_regex ]] || die "push base is not a full commit ID"
fi

# An all-zero target means the push deletes a ref. Nothing new is sent.
[[ "$to_ref" == "$zero_ref" ]] && exit 0

if [[ -z "$from_ref" || "$from_ref" == "$zero_ref" ]]; then
  commit_list="$(git rev-list "$to_ref")" ||
    die "unable to list commits for the push range"
else
  commit_list="$(git rev-list "${from_ref}..${to_ref}")" ||
    die "unable to list commits for the push range"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

commit_msg_file="${tmp_dir}/commit_messages.txt"
added_lines_file="${tmp_dir}/added_lines.txt"
paths_file="${tmp_dir}/paths.txt"

# Tags publish their own message in addition to the referenced commits.
object_type="$(git cat-file -t "$to_ref")"
if [[ "$object_type" == tag ]]; then
  git cat-file tag "$to_ref" >"$commit_msg_file"
else
  : >"$commit_msg_file"
fi
bash "${script_dir}/check-sensitive-text.sh" --context=push-tag "$commit_msg_file"
[[ -n "$commit_list" ]] || exit 0

# These options override user git config. Without them, log.showRoot,
# log.diffMerges, or i18n.logOutputEncoding can hide a root commit, a
# merge, or a commit message. --no-pager keeps a pager from filtering output.
printf '%s\n' "$commit_list" |
  git --no-pager log --stdin --no-walk=unsorted --encoding=UTF-8 --no-notes \
    --format='%H%n%s%n%b%n' >>"${commit_msg_file}"

# Keep the patch so the scanner can report source file and new-file line.
# Forced text and disabled drivers preserve the real bytes for normalization.
printf '%s\n' "$commit_list" |
  git --no-pager -c core.quotePath=true log --stdin --no-walk=unsorted --root --diff-merges=first-parent \
    --no-renames --no-notes --format= --patch --src-prefix=a/ --dst-prefix=b/ \
    --text --no-color --unified=0 --no-ext-diff --no-textconv >"${added_lines_file}"

bash "${script_dir}/check-sensitive-text.sh" --context=push-commit-message "${commit_msg_file}"
bash "${script_dir}/check-sensitive-text.sh" --context=push-added-lines --patch "${added_lines_file}"

printf '%s\n' "$commit_list" |
  git --no-pager -c core.quotePath=false diff-tree --stdin --root -r \
    --diff-merges=first-parent --no-renames --no-commit-id --name-only >"$paths_file"
bash "${script_dir}/check-sensitive-text.sh" --context=push-paths "$paths_file"
