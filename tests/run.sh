#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d -t commands_tests.XXXXXX)"
passed=0
watcher_pid=""

cleanup() {
  if [[ -n "$watcher_pid" ]]; then
    kill -TERM "$watcher_pid" >/dev/null 2>&1 || true
    wait "$watcher_pid" 2>/dev/null || true
  fi
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

# Stubs exit without reading stdin, like a clipboard tool that fails early.
make_clipboard_stub() {
  local bin_dir="$1" tool
  mkdir -p "$bin_dir"
  for tool in pbcopy osascript; do
    printf '#!/usr/bin/env sh\nexit 0\n' >"$bin_dir/$tool"
    chmod +x "$bin_dir/$tool"
  done
}

# True when PATH=/usr/bin:/bin has no clipboard tools (Linux CI, not macOS).
clipboard_tools_absent() {
  ! PATH="/usr/bin:/bin" command -v pbcopy >/dev/null 2>&1 &&
    ! PATH="/usr/bin:/bin" command -v osascript >/dev/null 2>&1
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

  # One unreadable notebook must not stop the others.
  local bad_notebook="$work_dir/a-bad.ipynb" error_file="$work_dir/error.txt"
  printf '\377\376 not utf-8\n' >"$bad_notebook"
  printf '%s\n' \
    '{"cells":[{"cell_type":"code","execution_count":1,"outputs":[{"output_type":"stream","text":["x"]}],"source":["x"]}],"metadata":{},"nbformat":4,"nbformat_minor":5}' \
    >"$work_dir/b-good.ipynb"
  if "$repo_root/scripts/clear_notebook_outputs.sh" "$work_dir" >/dev/null 2>"$error_file"; then
    fail "a bad notebook did not make the run fail"
  fi
  assert_contains "$error_file" "failed to read"
  assert_not_contains "$error_file" "Traceback"
  assert_contains "$work_dir/b-good.ipynb" '"outputs": []'

  if "$repo_root/scripts/clear_notebook_outputs.sh" >/dev/null 2>"$error_file"; then
    fail "missing path argument was accepted"
  fi
  assert_contains "$error_file" "Usage:"
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
  printf 'make body\n' >"$input_dir/Makefile"
  printf 'readme body\n' >"$input_dir/README"
  printf 'trailing dot body\n' >"$input_dir/foo."
  printf 'space body\n' >"$input_dir/a b.txt"
  printf 'newline body\n' >"$input_dir/new"$'\n'"line.txt"
  mkdir -p "$input_dir/.hidden"
  printf 'hidden body\n' >"$input_dir/.hidden/keep.txt"
  printf 'old output\n' >"$output_file"
  git -C "$input_dir" init -q

  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$output_file" "$input_dir" >/dev/null

  assert_contains "$output_file" "# File: keep.txt"
  assert_contains "$output_file" "include me"
  assert_contains "$output_file" "make body"
  assert_contains "$output_file" "readme body"
  assert_contains "$output_file" "space body"
  assert_contains "$output_file" "newline body"
  assert_not_contains "$output_file" "trailing dot body"
  assert_not_contains "$output_file" "hidden body"
  assert_not_contains "$output_file" "ignore me"
  assert_not_contains "$output_file" "do not share"
  assert_not_contains "$output_file" "old output"
  assert_not_contains "$output_file" "# File: bundle.txt"

  # The same input outside Git uses find, and must give the same files.
  local plain_dir="$work_dir/plain" plain_output="$work_dir/plain.txt"
  mkdir -p "$plain_dir"
  cp "$input_dir/keep.txt" "$input_dir/a b.txt" "$input_dir/new"$'\n'"line.txt" "$plain_dir/"
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$plain_output" "$plain_dir" >/dev/null
  assert_contains "$plain_output" "space body"
  assert_contains "$plain_output" "newline body"
  pass "deterministic LLM bundle output"
}

test_llm_copy_secrets() {
  local work_dir="$test_root/llm-copy-secrets"
  local input_dir="$work_dir/input"
  local bin_dir="$work_dir/bin"
  local output_file="$work_dir/bundle.txt"
  local error_file="$work_dir/error.txt"
  local token
  mkdir -p "$input_dir"
  make_clipboard_stub "$bin_dir"
  printf -v token '%s%s' 'ghp_' 'abcdefghijklmnopqrstuvwxyz'

  printf 'keep body\n' >"$input_dir/keep.txt"
  printf 'credential body\n' >"$input_dir/credentials.json"
  printf 'secret body\n' >"$input_dir/secrets.toml"
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$output_file" "$input_dir" >/dev/null 2>"$error_file"
  assert_contains "$output_file" "keep body"
  assert_not_contains "$output_file" "credential body"
  assert_not_contains "$output_file" "secret body"
  assert_contains "$error_file" "skipping credentials.json"

  printf 'value: %s\n' "$token" >"$input_dir/notes.txt"
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$output_file" "$input_dir" >/dev/null 2>"$error_file" ||
    fail "safe files were refused because another file was sensitive"
  assert_contains "$output_file" "keep body"
  assert_not_contains "$output_file" "$token"
  assert_contains "$error_file" "notes.txt"
  assert_contains "$error_file" "credential-like content"
  assert_not_contains "$error_file" "$token"
  [[ -z "$(find "$work_dir" -name '.llm_bundle.*')" ]] ||
    fail "skipped bundle left a temporary file"

  printf 'previous bundle\n' >"$output_file"
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$output_file" "$input_dir/notes.txt" >/dev/null 2>"$error_file" ||
    fail "skipping the only sensitive file failed"
  assert_contains "$output_file" "previous bundle"

  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" --allow-sensitive \
    --string --save-path "$output_file" "$input_dir" >/dev/null 2>&1 ||
    fail "--allow-sensitive did not copy the bundle"
  assert_contains "$output_file" "$token"

  # This repository has no real token, so it must copy without the override.
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" \
    --string --save-path "$output_file" "$repo_root" >/dev/null 2>&1 ||
    fail "llm_copy blocked this repository"
  pass "LLM bundle skips secret files"
}

test_llm_copy_temp_files() {
  local work_dir="$test_root/llm-copy-temp"
  local bin_dir="$work_dir/bin"
  local tmp_dir="$work_dir/tmp"
  mkdir -p "$work_dir/input" "$tmp_dir"
  make_clipboard_stub "$bin_dir"
  printf 'body\n' >"$work_dir/input/keep.txt"

  TMPDIR="$tmp_dir" PATH="$bin_dir:/usr/bin:/bin" \
    "$repo_root/scripts/llm_copy.sh" --string "$work_dir/input" >/dev/null
  [[ -z "$(ls -A "$tmp_dir")" ]] || fail "--string left a temporary file"

  TMPDIR="$tmp_dir" PATH="$bin_dir:/usr/bin:/bin" \
    "$repo_root/scripts/llm_copy.sh" "$work_dir/input" >/dev/null
  local kept
  kept="$(ls -A "$tmp_dir")"
  [[ "$kept" == llm_bundle.*.txt && "$kept" != *$'\n'* ]] ||
    fail "file mode should keep exactly one .txt file, found: $kept"

  if clipboard_tools_absent; then
    local saved="$work_dir/saved.txt" error_file="$work_dir/error.txt"
    PATH="/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" --string \
      --save-path "$saved" "$work_dir/input" >/dev/null 2>"$error_file" ||
      fail "--save-path failed without a clipboard tool"
    assert_contains "$saved" "body"
    assert_contains "$error_file" "file was saved only"
    if PATH="/usr/bin:/bin" "$repo_root/scripts/llm_copy.sh" --string \
      "$work_dir/input" >/dev/null 2>"$error_file"; then
      fail "missing clipboard tool without --save-path was accepted"
    fi
    assert_contains "$error_file" "--save-path"
  fi
  pass "LLM bundle temporary files and clipboard fallback"
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

  # A diff driver from the repo config must not run.
  local marker="$work_dir/external-diff-ran"
  printf '#!/usr/bin/env sh\n: >"%s"\n' "$marker" >"$work_dir/external-diff.sh"
  chmod +x "$work_dir/external-diff.sh"
  git -C "$repo_dir" config diff.external "$work_dir/external-diff.sh"
  PATH="$bin_dir:/usr/bin:/bin" "$repo_root/scripts/llm_git_diff.sh" \
    "$repo_dir" --string --save-path "$output_file" --staged >/dev/null
  [[ ! -e "$marker" ]] || fail "llm_git_diff ran an external diff driver"
  assert_contains "$output_file" "+after"
  git -C "$repo_dir" config --unset diff.external

  if clipboard_tools_absent; then
    PATH="/usr/bin:/bin" "$repo_root/scripts/llm_git_diff.sh" \
      "$repo_dir" --save-path "$output_file" --staged >/dev/null 2>&1 ||
      fail "llm_git_diff --save-path failed without a clipboard tool"
    assert_contains "$output_file" "+after"
  fi
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

  local dry_run_output="$test_root/branches-dry-run.txt"
  (
    cd "$repo_dir"
    "$repo_root/scripts/git_clean_branches.sh" --dry-run >"$dry_run_output"
  )
  assert_contains "$dry_run_output" "Would delete merged"
  assert_not_contains "$dry_run_output" "unmerged"
  git -C "$repo_dir" show-ref --verify --quiet refs/heads/merged ||
    fail "dry run deleted a branch"

  # A dry run must not contact remotes, so a missing remote is not an error.
  git -C "$repo_dir" remote add origin "$test_root/missing-remote"
  (
    cd "$repo_dir"
    "$repo_root/scripts/git_clean_branches.sh" --dry-run >/dev/null 2>&1
  ) || fail "dry run tried to fetch"
  git -C "$repo_dir" remote remove origin

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

# Append a line to a file until it shows up in the output, for up to 5s.
# tail -n0 skips lines written before it opens the file, so one write is
# not enough.
append_until_seen() {
  local log_file="$1" line="$2" output_file="$3" attempts=0
  while [[ "$attempts" -lt 50 ]]; do
    printf '%s\n' "$line" >>"$log_file"
    grep -Fq -- "$line" "$output_file" && return 0
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "'$line' did not appear in multitail output"
}

test_multitail() {
  local work_dir="$test_root/multitail"
  # A leading "-" checks that tail gets the file names after "--".
  local logs_dir="-logs"
  local output_file="$work_dir/output.txt"
  mkdir -p "$work_dir/$logs_dir"
  : >"$work_dir/$logs_dir/first file.log"

  (
    cd "$work_dir"
    exec "$repo_root/scripts/multitail.sh" "$logs_dir"
  ) >"$output_file" 2>&1 &
  watcher_pid=$!

  append_until_seen "$work_dir/$logs_dir/first file.log" "first event" "$output_file"
  : >"$work_dir/$logs_dir/second.log"
  append_until_seen "$work_dir/$logs_dir/second.log" "second event" "$output_file"

  kill -TERM "$watcher_pid" >/dev/null 2>&1 || true
  wait "$watcher_pid" 2>/dev/null || true
  watcher_pid=""
  assert_not_contains "$output_file" "unbound variable"
  assert_not_contains "$output_file" "usage"
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

  # Build the paths at run time so this file does not trip the scanners.
  local blocked_path users="Users" home="home" windows_users="users"
  printf 'path: C:\\%s\\YOU\n' "$windows_users" >"$mixed_path_file"
  bash "$repo_root/scripts/security/check-sensitive-text.sh" \
    --context=path-test "$mixed_path_file" >/dev/null 2>"$error_file" ||
    fail "Windows placeholder path was blocked"
  for blocked_path in \
    "/$users/YOU /$users/private-example" \
    "/$users/YOUNG" \
    "/$home/username2" \
    "C:\\$users\\private-example" \
    "C:\\$windows_users\\private-example"; do
    printf 'path: %s\n' "$blocked_path" >"$mixed_path_file"
    if bash "$repo_root/scripts/security/check-sensitive-text.sh" \
      --context=path-test "$mixed_path_file" >/dev/null 2>&1; then
      fail "local path was not blocked: $blocked_path"
    fi
  done

  if bash "$repo_root/scripts/security/check-sensitive-text.sh" \
    --context=test "$work_dir/missing.txt" >/dev/null 2>&1; then
    fail "missing input file was accepted"
  fi
  pass "redacted sensitive-text reports"
}

push_range_check() {
  local repo_dir="$1"
  shift
  (
    cd "$repo_dir"
    bash "$repo_root/scripts/security/check-push-range.sh" "$@"
  )
}

test_push_range_policy() {
  local repo_dir="$test_root/push-range"
  local error_file="$test_root/push-range-error.txt"
  local secret_value private_path
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.invalid"
  printf -v secret_value '%s%s' 'abc123456' '789XYZ'
  printf -v private_path '/%s/%s' home private-example

  printf 'token=%s\n' "$secret_value" >"$repo_dir/example.txt"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "Add old value"
  local secret_commit
  secret_commit="$(git -C "$repo_dir" rev-parse HEAD)"

  printf 'safe\n' >"$repo_dir/example.txt"
  git -C "$repo_dir" commit -qam "Remove old value"
  local removal_commit
  removal_commit="$(git -C "$repo_dir" rev-parse HEAD)"

  PRE_COMMIT_FROM_REF="$secret_commit" PRE_COMMIT_TO_REF="$removal_commit" \
    push_range_check "$repo_dir" >/dev/null 2>&1 ||
    fail "removing sensitive text was blocked"

  printf 'token=%s\n' "$secret_value" >"$repo_dir/example.txt"
  git -C "$repo_dir" commit -qam "Add unsafe value"
  local unsafe_commit
  unsafe_commit="$(git -C "$repo_dir" rev-parse HEAD)"

  if PRE_COMMIT_FROM_REF="$removal_commit" PRE_COMMIT_TO_REF="$unsafe_commit" \
    push_range_check "$repo_dir" >/dev/null 2>"$error_file"; then
    fail "added sensitive text was not blocked"
  fi
  assert_not_contains "$error_file" "$secret_value"

  # pre-commit sets no range when the push includes the root commit.
  if PRE_COMMIT_LOCAL_BRANCH=refs/heads/main \
    push_range_check "$repo_dir" >/dev/null 2>&1; then
    fail "root push without a pre-commit range was not scanned"
  fi
  if push_range_check "$repo_dir" >/dev/null 2>&1; then
    fail "missing push range was accepted"
  fi
  if push_range_check "$repo_dir" --from "$removal_commit" --to --all >/dev/null 2>&1; then
    fail "non-commit push target was accepted"
  fi
  if push_range_check "$test_root" --to "$unsafe_commit" >/dev/null 2>"$error_file"; then
    fail "git failure outside a repository was accepted"
  fi
  assert_contains "$error_file" "unable to list commits"

  # An added line that starts with "++" is content, not a diff header.
  printf 'safe\n' >"$repo_dir/example.txt"
  git -C "$repo_dir" commit -qam "Remove unsafe value"
  local clean_commit
  clean_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  printf '++ %s\n' "$private_path" >"$repo_dir/plus.txt"
  git -C "$repo_dir" add plus.txt
  git -C "$repo_dir" commit -q -m "Add plus line"
  if push_range_check "$repo_dir" --from "$clean_commit" \
    --to "$(git -C "$repo_dir" rev-parse HEAD)" >/dev/null 2>"$error_file"; then
    fail "added line starting with ++ was not scanned"
  fi
  assert_contains "$error_file" "local machine path in plus.txt on line(s): 1"
  assert_not_contains "$error_file" "$private_path"

  # A merge commit that adds a value of its own must be scanned.
  git -C "$repo_dir" switch -q -c side "$clean_commit"
  printf 'side\n' >"$repo_dir/side.txt"
  git -C "$repo_dir" add side.txt
  git -C "$repo_dir" commit -q -m "Add side file"
  local side_commit
  side_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  git -C "$repo_dir" switch -q -c merged "$clean_commit"
  git -C "$repo_dir" merge -q --no-ff --no-commit side >/dev/null 2>&1
  printf 'token=%s\n' "$secret_value" >"$repo_dir/merge.txt"
  git -C "$repo_dir" add merge.txt
  git -C "$repo_dir" commit -q -m "Merge side"
  if push_range_check "$repo_dir" --from "$side_commit" \
    --to "$(git -C "$repo_dir" rev-parse HEAD)" >/dev/null 2>"$error_file"; then
    fail "value added by a merge commit was not blocked"
  fi
  assert_not_contains "$error_file" "$secret_value"
  pass "fail-closed push policy"
}

test_help
test_notebook_cleanup
test_llm_copy
test_llm_copy_secrets
test_llm_copy_temp_files
test_llm_git_diff
test_branch_cleanup
test_multitail
test_sensitive_text_policy
test_push_range_policy

regression_count=0
for regression in nul attributes json project pem remote filename tag staged copy-names copy-json copy-project copy-pem notebook textconv clean clean-staged assignment-forms copy-skip copy-code utf16 nul-before latin1-clean latin1-direct config-root config-merge config-encoding nested-staged submodule-textconv jwt jwt-staged jwt-push copy-jwt token-formats token-boundaries source-staged source-push; do
  bash "$repo_root/tests/regressions.sh" "$regression"
  regression_count=$((regression_count + 1))
done

# These cases need gitleaks. CI installs it and sets COMMANDS_TEST_REQUIRE_GITLEAKS.
if command -v gitleaks >/dev/null 2>&1; then
  for regression in gitleaks-paths gitleaks-range; do
    bash "$repo_root/tests/regressions.sh" "$regression"
    regression_count=$((regression_count + 1))
  done
elif [[ "${COMMANDS_TEST_REQUIRE_GITLEAKS:-}" == 1 ]]; then
  fail "gitleaks is not on PATH"
else
  echo "skip - gitleaks tests (gitleaks is not on PATH)"
fi

echo "All $((passed + regression_count)) tests passed."
