#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d -t commands_tests.XXXXXX)"
passed=0

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  passed=$((passed + 1))
  echo "ok $passed - $1"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "did not expect '$unexpected' in $file"
  fi
}

make_clipboard_stub() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env sh\nexit 0\n' >"$bin_dir/pbcopy"
  chmod +x "$bin_dir/pbcopy"
}

test_help() {
  local script
  for script in \
    clear_notebook_outputs.sh \
    git_clean_branches.sh \
    llm_copy.sh \
    llm_git_diff.sh \
    multitail.sh; do
    "$repo_root/scripts/$script" --help >/dev/null 2>&1 ||
      fail "$script --help failed"
  done
  pass "user-facing help"
}

test_notebook_cleanup() {
  local work_dir="$test_root/notebook"
  local notebook="$work_dir/example.ipynb"
  mkdir -p "$work_dir"
  printf '%s\n' \
    '{"cells":[{"cell_type":"code","execution_count":4,"outputs":[{"output_type":"stream","text":["hello"]}],"source":["print(1)"]},{"cell_type":"markdown","execution_count":9,"metadata":{},"source":["note"]}],"metadata":{},"nbformat":4,"nbformat_minor":5}' \
    >"$notebook"
  chmod 640 "$notebook"

  "$repo_root/scripts/clear_notebook_outputs.sh" "$notebook" >/dev/null
  python3 - "$notebook" <<'PY'
import json
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
notebook = json.loads(path.read_text(encoding="utf-8"))
code, markdown = notebook["cells"]
assert code["outputs"] == []
assert code["execution_count"] is None
assert markdown["execution_count"] == 9
assert stat.S_IMODE(path.stat().st_mode) == 0o640
PY

  before="$(cksum "$notebook")"
  "$repo_root/scripts/clear_notebook_outputs.sh" "$notebook" >/dev/null
  after="$(cksum "$notebook")"
  [[ "$before" == "$after" ]] || fail "notebook cleanup was not idempotent"
  pass "atomic notebook cleanup"
}

test_llm_copy() {
  local work_dir="$test_root/llm-copy"
  local input_dir="$work_dir/input"
  local bin_dir="$work_dir/bin"
  local output_file="$input_dir/bundle.txt"
  mkdir -p "$input_dir"
  make_clipboard_stub "$bin_dir"

  printf 'include me\n' >"$input_dir/keep.txt"
  printf 'ignore me\n' >"$input_dir/ignored.txt"
  printf 'do not share\n' >"$input_dir/config.env"
  printf 'ignored.txt\n' >"$input_dir/.gitignore"
  printf 'old output\n' >"$output_file"
  git -C "$input_dir" init -q

  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$output_file" "$input_dir" >/dev/null

  assert_contains "$output_file" "# File: keep.txt"
  assert_contains "$output_file" "include me"
  assert_not_contains "$output_file" "ignore me"
  assert_not_contains "$output_file" "do not share"
  assert_not_contains "$output_file" "old output"
  assert_not_contains "$output_file" "# File: bundle.txt"
  pass "deterministic LLM bundle output"
}

test_llm_git_diff() {
  local work_dir="$test_root/llm-diff"
  local repo_dir="$work_dir/repo"
  local bin_dir="$work_dir/bin"
  local output_file="$repo_dir/diff-output.txt"
  mkdir -p "$repo_dir"
  make_clipboard_stub "$bin_dir"

  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.invalid"
  printf 'before\n' >"$repo_dir/tracked.txt"
  git -C "$repo_dir" add tracked.txt
  git -C "$repo_dir" commit -q -m "Add tracked file"
  printf 'after\n' >"$repo_dir/tracked.txt"
  printf 'new\n' >"$repo_dir/untracked.txt"
  printf 'old output\n' >"$output_file"

  before_status="$(git -C "$repo_dir" status --porcelain=v2)"
  if PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_git_diff.sh" \
    "$repo_dir" --string --save-path "$output_file" \
    --definitely-not-a-git-diff-option >/dev/null 2>&1; then
    fail "invalid git diff option unexpectedly succeeded"
  fi
  assert_contains "$output_file" "old output"

  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_git_diff.sh" \
    "$repo_dir" --string --save-path "$output_file" >/dev/null
  after_status="$(git -C "$repo_dir" status --porcelain=v2)"

  [[ "$before_status" == "$after_status" ]] || fail "llm_git_diff changed the Git index"
  assert_contains "$output_file" "tracked.txt"
  assert_contains "$output_file" "untracked.txt"
  assert_contains "$output_file" "+new"
  assert_not_contains "$output_file" "diff-output.txt"
  assert_not_contains "$output_file" "old output"

  git -C "$repo_dir" add tracked.txt
  before_status="$(git -C "$repo_dir" status --porcelain=v2)"
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_git_diff.sh" \
    "$repo_dir" --string --save-path "$output_file" --staged >/dev/null
  after_status="$(git -C "$repo_dir" status --porcelain=v2)"
  [[ "$before_status" == "$after_status" ]] || fail "staged diff changed the Git index"
  assert_contains "$output_file" "untracked.txt"
  assert_contains "$output_file" "+new"
  pass "read-only Git diff generation"
}

test_branch_cleanup() {
  local repo_dir="$test_root/branches"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.invalid"
  printf 'base\n' >"$repo_dir/file.txt"
  git -C "$repo_dir" add file.txt
  git -C "$repo_dir" commit -q -m "Add base"

  git -C "$repo_dir" switch -q -c merged
  printf 'merged\n' >>"$repo_dir/file.txt"
  git -C "$repo_dir" commit -qam "Add merged work"
  git -C "$repo_dir" switch -q main
  git -C "$repo_dir" merge -q --ff-only merged

  git -C "$repo_dir" switch -q -c unmerged HEAD^
  printf 'unmerged\n' >"$repo_dir/other.txt"
  git -C "$repo_dir" add other.txt
  git -C "$repo_dir" commit -q -m "Add unmerged work"
  git -C "$repo_dir" switch -q main

  (
    cd "$repo_dir"
    "$repo_root/scripts/git_clean_branches.sh" >/dev/null
  )

  if git -C "$repo_dir" show-ref --verify --quiet refs/heads/merged; then
    fail "merged branch was not deleted"
  fi
  git -C "$repo_dir" show-ref --verify --quiet refs/heads/unmerged ||
    fail "unmerged branch was deleted"
  pass "safe merged-branch cleanup"
}

test_multitail() {
  local work_dir="$test_root/multitail"
  local logs_dir="$work_dir/logs"
  local output_file="$work_dir/output.txt"
  mkdir -p "$logs_dir"
  : >"$logs_dir/first file.log"

  "$repo_root/scripts/multitail.sh" "$logs_dir" >"$output_file" 2>&1 &
  local watcher_pid=$!
  sleep 0.3
  printf 'first event\n' >>"$logs_dir/first file.log"
  sleep 1.2
  : >"$logs_dir/second.log"
  sleep 1.2
  printf 'second event\n' >>"$logs_dir/second.log"
  sleep 0.3
  kill -TERM "$watcher_pid" >/dev/null 2>&1 || true
  wait "$watcher_pid" 2>/dev/null || true

  assert_contains "$output_file" "first event"
  assert_contains "$output_file" "second event"
  pass "multitail process ownership"
}

test_sensitive_text_policy() {
  local work_dir="$test_root/security"
  local safe_file="$work_dir/safe.txt"
  local bad_file="$work_dir/bad.txt"
  local mixed_path_file="$work_dir/mixed-path.txt"
  local error_file="$work_dir/error.txt"
  local secret_value
  mkdir -p "$work_dir"
  printf 'example path: /Users/YOU/project\n' >"$safe_file"
  printf -v secret_value '%s%s' 'abc123456' '789XYZ'
  printf 'token=%s\n' "$secret_value" >"$bad_file"

  bash "$repo_root/scripts/security/check-sensitive-text.sh" \
    --context=test "$safe_file" >/dev/null 2>&1
  if bash "$repo_root/scripts/security/check-sensitive-text.sh" \
    --context=test "$bad_file" >/dev/null 2>"$error_file"; then
    fail "sensitive text was not blocked"
  fi
  assert_contains "$error_file" "credential-like assignment on line(s): 1"
  assert_not_contains "$error_file" "$secret_value"
  assert_not_contains "$error_file" "$work_dir"

  if PATH="/usr/bin:/bin" bash "$repo_root/scripts/security/check-sensitive-text.sh" \
    --context=fallback-test "$bad_file" >/dev/null 2>"$error_file"; then
    fail "fallback sensitive-text check did not block the value"
  fi
  assert_not_contains "$error_file" "$secret_value"

  printf 'paths: /Users/%s /Users/%s\n' YOU private-example >"$mixed_path_file"
  if bash "$repo_root/scripts/security/check-sensitive-text.sh" \
    --context=mixed-path-test "$mixed_path_file" >/dev/null 2>"$error_file"; then
    fail "real local path beside a placeholder was not blocked"
  fi
  pass "redacted sensitive-text reports"
}

test_push_range_policy() {
  local repo_dir="$test_root/push-range"
  local error_file="$test_root/push-range-error.txt"
  local secret_value
  mkdir -p "$repo_dir/scripts"
  cp -R "$repo_root/scripts/security" "$repo_dir/scripts/security"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.invalid"
  printf -v secret_value '%s%s' 'abc123456' '789XYZ'

  printf 'token=%s\n' "$secret_value" >"$repo_dir/example.txt"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "Add old value"
  local secret_commit
  secret_commit="$(git -C "$repo_dir" rev-parse HEAD)"

  printf 'safe\n' >"$repo_dir/example.txt"
  git -C "$repo_dir" commit -qam "Remove old value"
  local removal_commit
  removal_commit="$(git -C "$repo_dir" rev-parse HEAD)"

  (
    cd "$repo_dir"
    PRE_COMMIT_FROM_REF="$secret_commit" PRE_COMMIT_TO_REF="$removal_commit" \
      bash scripts/security/check-push-range.sh
  ) >/dev/null 2>&1 || fail "removing sensitive text was blocked"

  printf 'token=%s\n' "$secret_value" >"$repo_dir/example.txt"
  git -C "$repo_dir" commit -qam "Add unsafe value"
  local unsafe_commit
  unsafe_commit="$(git -C "$repo_dir" rev-parse HEAD)"

  if (
    cd "$repo_dir"
    PRE_COMMIT_FROM_REF="$removal_commit" PRE_COMMIT_TO_REF="$unsafe_commit" \
      bash scripts/security/check-push-range.sh
  ) >/dev/null 2>"$error_file"; then
    fail "added sensitive text was not blocked"
  fi
  assert_not_contains "$error_file" "$secret_value"
  pass "added-line push policy"
}

test_help
test_notebook_cleanup
test_llm_copy
test_llm_git_diff
test_branch_cleanup
test_multitail
test_sensitive_text_policy
test_push_range_policy

echo "All $passed tests passed."
