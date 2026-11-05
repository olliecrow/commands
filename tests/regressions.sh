#!/usr/bin/env bash
set -euo pipefail
repo_root="${COMMANDS_TEST_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/commands_regressions.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
# A crash or a usage error is not a block. Require the policy exit and text.
blocked() {
  local status=0
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  [[ "$status" -eq 1 ]] || fail "expected status 1, got $status"
  grep -q "policy violation" "$work/stderr" || fail "expected a policy violation"
}
skipped_copy() {
  local status=0
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  [[ "$status" -eq 0 ]] || fail "expected the sensitive file to be skipped, got $status"
  grep -q "credential-like content" "$work/stderr" || fail "expected credential-like content"
}
clean_text() {
  local status=0
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  [[ "$status" -eq 0 ]] || fail "expected a clean scan, got $status"
  if grep -q "policy violation" "$work/stderr"; then
    fail "clean input was blocked"
  fi
}
init_repo() {
  mkdir -p "$work/repo"
  git -C "$work/repo" init -q
  git -C "$work/repo" config user.name Test
  git -C "$work/repo" config user.email test@example.invalid
  git -C "$work/repo" commit -q --allow-empty -m Base
  base="$(git -C "$work/repo" rev-parse HEAD)"
}
commit_files() {
  git -C "$work/repo" add .
  git -C "$work/repo" commit -qm Fixture
  tip="$(git -C "$work/repo" rev-parse HEAD)"
}
scan_staged() {
  (cd "$work/repo" && bash "$repo_root/scripts/security/check-staged.sh")
}
scan_push() {
  (cd "$work/repo" && bash "$repo_root/scripts/security/check-push-range.sh" "$@")
}
# Synthetic values are assembled at runtime and never printed.
printf -v value '%s%s' abcd1234 efgh5678
printf -v project '%s%s%s' sk- proj- abcdefghijklmnopqrstuvwxyz0123456789
case "${1:-}" in
  nul|attributes)
    init_repo
    printf 'api_key=%s\n' "$value" >"$work/repo/data.txt"
    if [[ "$1" == nul ]]; then printf '\0' >>"$work/repo/data.txt";
    else printf '* -diff\n' >"$work/repo/.gitattributes"; fi
    commit_files
    blocked scan_push --from "$base" --to "$tip"
    ;;
  json|project|pem)
    case "$1" in
      json) printf '{"client_secret":"%s"}\n' "$value" >"$work/input" ;;
      project) printf '%s\n' "$project" >"$work/input" ;;
      pem) printf '%s%s\n' '-----BEGIN RSA ' 'PRIVATE KEY-----' >"$work/input" ;;
    esac
    blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    ;;
  remote)
    init_repo
    printf 'api_key=%s\n' "$value" >"$work/repo/data.txt"
    commit_files
    printf 'clean\n' >"$work/repo/data.txt"
    commit_files
    git -C "$work/repo" update-ref refs/remotes/backup/main "$tip"
    PRE_COMMIT_REMOTE_NAME=destination blocked scan_push --to "$tip"
    ;;
  staged)
    init_repo
    printf '/%s/%s/app\n' home private-example >"$work/repo/data.txt"
    git -C "$work/repo" add .
    blocked scan_staged
    ;;
  filename|tag)
    init_repo
    if [[ "$1" == filename ]]; then
      printf 'clean\n' >"$work/repo/$project"
      commit_files
    else
      git -C "$work/repo" tag -a fixture -m "api_key=$value"
      tip="$(git -C "$work/repo" rev-parse refs/tags/fixture)"
    fi
    blocked scan_push --from "$base" --to "$tip"
    ;;
  copy-names)
    mkdir -p "$work/input"
    printf 'safe\n' >"$work/input/keep.txt"
    for name in Secrets.toml secret.txt secret.yaml client_secret.json credentials.toml aws.ini PRIVATE.KEY id_rsa.txt .env.txt; do
      printf 'excluded body\n' >"$work/input/$name"
    done
    bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/input" >"$work/stdout" 2>"$work/stderr"
    if grep -q 'excluded body' "$work/bundle"; then fail "secret filename copied"; fi
    bash "$repo_root/scripts/llm_copy.sh" --allow-sensitive --save-path "$work/override" "$work/input/Secrets.toml" >"$work/stdout" 2>"$work/stderr"
    grep -q 'excluded body' "$work/override" || fail "filename override failed"
    ;;
  copy-json|copy-project|copy-pem)
    case "$1" in
      copy-json) printf '{"client_secret":"%s"}\n' "$value" >"$work/notes.txt" ;;
      copy-project) printf '%s\n' "$project" >"$work/notes.txt" ;;
      copy-pem) printf '%s%s\n' '-----BEGIN OPENSSH ' 'PRIVATE KEY-----' >"$work/notes.txt" ;;
    esac
    printf 'previous bundle\n' >"$work/bundle"
    skipped_copy bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/notes.txt"
    grep -qx 'previous bundle' "$work/bundle" || fail "output changed while skipping"
    bash "$repo_root/scripts/llm_copy.sh" --allow-sensitive --save-path "$work/bundle" "$work/notes.txt" >"$work/stdout" 2>"$work/stderr"
    grep -q '# File:' "$work/bundle" || fail "content override failed"
    ;;
  notebook)
    mkdir -p "$work/tree"
    printf '%s\n' '{"cells":[{"cell_type":"code","outputs":[1],"execution_count":1}]}' >"$work/outside.ipynb"
    cp "$work/outside.ipynb" "$work/before"
    ln -s "$work/outside.ipynb" "$work/tree/link.ipynb"
    bash "$repo_root/scripts/clear_notebook_outputs.sh" "$work/tree" >"$work/stdout" 2>"$work/stderr"
    cmp "$work/before" "$work/outside.ipynb" || fail "outside notebook rewritten"
    bash "$repo_root/scripts/clear_notebook_outputs.sh" "$work/tree/link.ipynb" >"$work/stdout" 2>"$work/stderr"
    cmp "$work/before" "$work/outside.ipynb" || fail "explicit symlink rewritten"
    ;;
  textconv|clean|clean-staged)
    init_repo
    printf 'before\n' >"$work/repo/tracked.txt"
    printf '*.txt diff=unsafe filter=unsafe\n' >"$work/repo/.gitattributes"
    commit_files
    git -C "$work/repo" config diff.unsafe.textconv "touch '$work/textconv-ran'"
    git -C "$work/repo" config filter.unsafe.clean "touch '$work/clean-ran'; cat"
    printf 'after\n' >"$work/repo/tracked.txt"
    printf 'untracked content\n' >"$work/repo/new.txt"
    git -C "$work/repo" diff --cached --raw >"$work/index-before"
    args=()
    [[ "$1" != clean-staged ]] || args+=(--staged)
    bash "$repo_root/scripts/llm_git_diff.sh" "$work/repo" --save-path "$work/diff" ${args[@]+"${args[@]}"} >"$work/stdout" 2>"$work/stderr"
    if [[ "$1" == textconv ]]; then
      [[ ! -e "$work/textconv-ran" ]] || fail "textconv executed"
      grep -q '+after' "$work/diff" || fail "tracked content missing"
    else
      [[ ! -e "$work/clean-ran" ]] || fail "clean filter executed"
    fi
    grep -q '+untracked content' "$work/diff" || fail "untracked content missing"
    git -C "$work/repo" diff --cached --raw >"$work/index-after"
    cmp "$work/index-before" "$work/index-after" || fail "real index changed"
    ;;
  assignment-forms)
    printf -v shaped '%s%s' abcd1234 efgh5678
    printf -v letters '%s%s' abcdefgh ijklmnop
    printf 'SECRET_KEY = "%s"\n' "$shaped" >"$work/input"
    blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    printf 'aws_secret_access_key = %s\n' "$shaped" >"$work/input"
    blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    printf 'private_key = "%s"\n' "$shaped" >"$work/input"
    blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    printf 'db_passwd: %s\n' "$shaped" >"$work/input"
    blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    printf 'auth_token = _github_auth_token(request)\n' >"$work/input"
    clean_text bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    printf 'token = func(x)\n' >"$work/input"
    clean_text bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    printf 'api_key=%s\n' "$letters" >"$work/input"
    clean_text bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    ;;
  copy-skip|copy-code)
    if [[ "$1" == copy-code ]]; then
      printf 'auth_token = _github_auth_token(request)\n' >"$work/notes.py"
      bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/notes.py" >"$work/stdout" 2>"$work/stderr"
      grep -q 'auth_token = _github_auth_token(request)' "$work/bundle" || fail "ordinary code was not copied"
      if grep -q "credential-like content" "$work/stderr"; then
        fail "ordinary code was flagged"
      fi
    else
      mkdir -p "$work/input"
      printf 'keep body\n' >"$work/input/keep.txt"
      printf 'api_key=%s\n' "$value" >"$work/input/notes.txt"
      bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/input" >"$work/stdout" 2>"$work/stderr"
      grep -q 'keep body' "$work/bundle" || fail "safe file was dropped"
      if grep -q "$value" "$work/bundle"; then fail "sensitive file was copied"; fi
      grep -q "credential-like content" "$work/stderr" || fail "expected credential-like content"
      grep -q "notes.txt" "$work/stderr" || fail "sensitive file was not named"
      if grep -q "$value" "$work/stderr"; then fail "value was printed"; fi
    fi
    ;;
  *) fail "unknown regression case" ;;
esac
echo "ok - $1"
