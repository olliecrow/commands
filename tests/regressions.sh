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
# Run a command and require an exact exit status.
status_is() {
  local expected="$1" status=0
  shift
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  [[ "$status" -eq "$expected" ]] || fail "expected status $expected, got $status: $*"
}
clean_text() {
  local status=0
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  [[ "$status" -eq 0 ]] || fail "expected a clean scan, got $status"
  if grep -q "policy violation" "$work/stderr"; then
    fail "clean input was blocked"
  fi
}
# Stand in for awk builds that stop at NUL or reject non-UTF-8 bytes.
install_awk_stub() {
  local mode="$1"
  mkdir -p "$work/bin"
  printf '%s\n' "$mode" >"$work/bin/awk-mode"
  cat >"$work/bin/awk" <<'PY'
#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile

mode_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "awk-mode")
with open(mode_path, "r", encoding="ascii") as handle:
    mode = handle.read().strip()
real = "/usr/bin/awk"
args = sys.argv[1:]


def transform(data):
    if mode == "high" and any(byte > 127 or byte == 0 for byte in data):
        sys.stderr.write("multibyte conversion failure\n")
        raise SystemExit(2)
    if mode == "nul":
        return b"\n".join(part.split(b"\0", 1)[0] for part in data.split(b"\n"))
    return data


paths = []
if args and os.path.isfile(args[-1]) and not args[-1].startswith("-"):
    paths = [args[-1]]
    args = args[:-1]
temps = []
try:
    if paths:
        new_args = list(args)
        for path in paths:
            with open(path, "rb") as handle:
                data = transform(handle.read())
            temp = tempfile.NamedTemporaryFile(delete=False)
            temp.write(data)
            temp.close()
            temps.append(temp.name)
            new_args.append(temp.name)
        raise SystemExit(subprocess.run([real, *new_args]).returncode)
    raise SystemExit(subprocess.run([real, *args], input=transform(sys.stdin.buffer.read())).returncode)
finally:
    for path in temps:
        try:
            os.remove(path)
        except OSError:
            pass
PY
  chmod +x "$work/bin/awk"
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
printf -v jwt '%s.%s.%s' eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 eyJzdWIiOiJ0ZXN0In0 \
  c2lnbmF0dXJlLWZvci10ZXN0cy1vbmx5LW5vdC1yZWFs
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
  submodule-textconv)
    src="$work/src"
    mkdir -p "$src"
    git -C "$src" init -q
    git -C "$src" config user.name Test
    git -C "$src" config user.email test@example.invalid
    printf 'a\n' >"$src/f.txt"
    printf '*.txt diff=t\n' >"$src/.gitattributes"
    git -C "$src" add .
    git -C "$src" commit -q -m Source
    init_repo
    git -C "$work/repo" -c protocol.file.allow=always submodule -q add "$src" sub
    git -C "$work/repo" commit -q -m "Add submodule"
    git -C "$work/repo/sub" config diff.t.textconv "touch '$work/marker'; cat"
    printf 'b\n' >>"$work/repo/sub/f.txt"
    bash "$repo_root/scripts/llm_git_diff.sh" "$work/repo" --save-path "$work/diff" --submodule=diff >"$work/stdout" 2>"$work/stderr"
    [[ ! -e "$work/marker" ]] || fail "submodule textconv ran"
    ;;
  nested-staged)
    init_repo
    mkdir -p "$work/inner"
    git -C "$work/inner" init -q
    git -C "$work/inner" config user.name Test
    git -C "$work/inner" config user.email test@example.invalid
    printf 'inner\n' >"$work/inner/f.txt"
    git -C "$work/inner" add .
    git -C "$work/inner" commit -q -m Inner
    mv "$work/inner" "$work/repo/inner"
    before="$(git -C "$work/repo" status --porcelain=v2)"
    bash "$repo_root/scripts/llm_git_diff.sh" "$work/repo" --save-path "$work/diff" --staged >"$work/stdout" 2>"$work/stderr"
    grep -q "Subproject commit" "$work/diff" || fail "nested repository was not recorded"
    if grep -q "fatal:" "$work/stderr"; then fail "nested repository aborted the diff"; fi
    after="$(git -C "$work/repo" status --porcelain=v2)"
    [[ "$before" == "$after" ]] || fail "real index changed"
    git -C "$work/repo" init -q empty
    bash "$repo_root/scripts/llm_git_diff.sh" "$work/repo" --save-path "$work/diff" --staged >"$work/stdout" 2>"$work/stderr"
    grep -q "nested repository has no commits" "$work/stderr" || fail "empty nested repository was not skipped"
    if grep -q "fatal:" "$work/stderr"; then fail "empty nested repository aborted the diff"; fi
    ;;
  config-root|config-merge|config-encoding)
    case "$1" in
      config-root)
        mkdir -p "$work/rootrepo"
        git -C "$work/rootrepo" init -q -b main
        git -C "$work/rootrepo" config user.name Test
        git -C "$work/rootrepo" config user.email test@example.invalid
        printf 'api_key=%s\n' "$value" >"$work/rootrepo/a.txt"
        git -C "$work/rootrepo" add .
        git -C "$work/rootrepo" commit -q -m Root
        git -C "$work/rootrepo" config log.showRoot false
        tip="$(git -C "$work/rootrepo" rev-parse HEAD)"
        root_scan() { (cd "$work/rootrepo" && bash "$repo_root/scripts/security/check-push-range.sh" "$@"); }
        blocked root_scan --to "$tip"
        ;;
      config-merge)
        init_repo
        printf 'one\n' >"$work/repo/a.txt"
        commit_files
        base_branch="$(git -C "$work/repo" branch --show-current)"
        git -C "$work/repo" switch -q -c side
        printf 's\n' >"$work/repo/s.txt"
        commit_files
        side="$tip"
        git -C "$work/repo" switch -q "$base_branch"
        git -C "$work/repo" merge -q --no-ff --no-commit side >/dev/null 2>&1
        printf 'api_key=%s\n' "$value" >"$work/repo/evil.txt"
        git -C "$work/repo" add .
        git -C "$work/repo" commit -q -m Merge
        tip="$(git -C "$work/repo" rev-parse HEAD)"
        git -C "$work/repo" config log.diffMerges off
        blocked scan_push --from "$side" --to "$tip"
        ;;
      config-encoding)
        init_repo
        printf 'ok\n' >"$work/repo/a.txt"
        git -C "$work/repo" add .
        git -C "$work/repo" commit -q -m "api_key=$value"
        tip="$(git -C "$work/repo" rev-parse HEAD)"
        git -C "$work/repo" config i18n.logOutputEncoding UTF-16LE
        blocked scan_push --from "$base" --to "$tip"
        ;;
    esac
    ;;
  utf16|nul-before|latin1-clean|latin1-direct)
    case "$1" in
      utf16)
        init_repo
        python3 -c 'import sys; sys.stdout.buffer.write(sys.argv[1].encode("utf-16le"))' \
          "$(printf 'api_key=%s\n' "$value")" >"$work/repo/a.txt"
        commit_files
        blocked scan_push --from "$base" --to "$tip"
        ;;
      nul-before)
        install_awk_stub nul
        init_repo
        {
          printf 'x'
          printf '\0'
          printf 'api_key=%s\n' "$value"
        } >"$work/repo/a.txt"
        commit_files
        PATH="$work/bin:/usr/bin:/bin" blocked scan_push --from "$base" --to "$tip"
        ;;
      latin1-clean)
        install_awk_stub high
        init_repo
        printf 'caf\xe9 ok\n' >"$work/repo/a.txt"
        commit_files
        PATH="$work/bin:/usr/bin:/bin" clean_text scan_push --from "$base" --to "$tip"
        ;;
      latin1-direct)
        install_awk_stub high
        printf 'caf\xe9 ok\n' >"$work/input"
        PATH="$work/bin:/usr/bin:/bin" clean_text bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
        ;;
    esac
    ;;
  jwt|jwt-staged|jwt-push)
    if [[ "$1" == jwt ]]; then
      printf 'Authorization: Bearer %s\n' "$jwt" >"$work/input"
      blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
      if grep -q "$jwt" "$work/stderr"; then fail "value was printed"; fi
      # Dotted names and a token with no signature are not credentials.
      printf '%s\n' com.example.package_name_here a.b.c eyJhbGciOiJIUzI1NiJ9.e30 eyJhbGci.e30.short >"$work/input"
      clean_text bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/input"
    else
      init_repo
      printf '%s\n' "$jwt" >"$work/repo/notes.txt"
      if [[ "$1" == jwt-staged ]]; then
        git -C "$work/repo" add .
        blocked scan_staged
      else
        commit_files
        blocked scan_push --from "$base" --to "$tip"
      fi
    fi
    ;;
  copy-jwt)
    mkdir -p "$work/input"
    printf 'keep body\n' >"$work/input/keep.txt"
    printf 'session: %s\n' "$jwt" >"$work/input/notes.txt"
    skipped_copy bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/input"
    grep -q 'keep body' "$work/bundle" || fail "safe file was dropped"
    if grep -q "$jwt" "$work/bundle"; then fail "JWT was copied"; fi
    grep -q "notes.txt" "$work/stderr" || fail "sensitive file was not named"
    if grep -q "$jwt" "$work/stderr"; then fail "value was printed"; fi
    ;;
  token-formats)
    for prefix in sk-ant-oat01- sk-ant-api03- sk-ant-admin01- sk-proj- sk-svcacct- sk-admin- sk- ghp_ github_pat_11 gho_ ghu_ ghs_ ghr_; do
      printf '%s%s\n' "$prefix" abcdefghijklmnopqrstuvwxyz0123456789 >"$work/notes.txt"
      blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/notes.txt"
      skipped_copy bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/notes.txt"
    done
    ;;
  token-boundaries)
    init_repo
    printf '%s\n' 'task-list-item' 'risk-assessment' \
      'class="task-list-item-checkbox-v2"' 'the risk-assessment-for-new-users doc' \
      'see desk-booking_service_module' 'sk-abcd-efgh-ijkl-mnop-qrst' \
      'kubernetes-task-scheduler-configuration' '/dev/disk-by-partition-label-example' \
      'task-ant-colony-optimisation-notes' >"$work/repo/ordinary.txt"
    printf '%s%s\n' myghp_ abcdefghijklmnopqrstuvwxyz0123456789 >>"$work/repo/ordinary.txt"
    printf '%s%s\n' XXAKIA IOSFODNN7EXAMPLE >>"$work/repo/ordinary.txt"
    printf 'they%s\n' "$jwt" >>"$work/repo/ordinary.txt"
    clean_text bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/repo/ordinary.txt"
    git -C "$work/repo" add .
    clean_text scan_staged
    commit_files
    clean_text scan_push --from "$base" --to "$tip"
    bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/repo" >"$work/stdout" 2>"$work/stderr"
    grep -q '# File: ordinary.txt' "$work/bundle" || fail "ordinary text was skipped"
    if grep -q 'credential-like content' "$work/stderr"; then fail "ordinary text flagged"; fi
    printf '%s%s\n' AKIA IOSFODNN7EXAMPLE >"$work/notes.txt"
    blocked bash "$repo_root/scripts/security/check-sensitive-text.sh" "$work/notes.txt"
    skipped_copy bash "$repo_root/scripts/llm_copy.sh" --save-path "$work/bundle" "$work/notes.txt"
    ;;
  gitleaks-paths)
    # Paths are built at run time so this file does not trip the scanners.
    users=Users
    lower_users=users
    home=home
    mkdir -p "$work/tree"
    scan_tree() {
      printf 'path: %s\n' "$1" >"$work/tree/notes.txt"
      gitleaks dir --no-banner --redact --config "$repo_root/.gitleaks.toml" "$work/tree"
    }
    for path in "/$home/private-example/app" "/$home/private-example" "/$home/userbob" \
      "/$users/private-example" "/$users/YOUNG" "C:\\$users\\private-example" \
      "c:\\$lower_users\\private-example" "/$home/user/a /$home/private-example/b" \
      "/$users/YOU/a /$users/private-example"; do
      status_is 1 scan_tree "$path"
    done
    for path in "/$home/user/app" "/$users/YOU/app" "C:\\$users\\YOU\\app" "D:\\$lower_users\\username"; do
      status_is 0 scan_tree "$path"
    done
    ;;
  gitleaks-range)
    init_repo
    scan_range() { (cd "$work/repo" && bash "$repo_root/scripts/security/gitleaks-range.sh" "$@"); }
    printf 'one\ntwo\n' >"$work/repo/a.txt"
    commit_files
    clean="$tip"
    status_is 0 scan_range --from "$base" --to "$clean"
    status_is 0 scan_range --to "$clean"
    status_is 0 scan_range --from "$clean" --to "$clean"
    grep -q "no commits to scan" "$work/stdout" || fail "empty range was not reported"
    # A commit that only removes lines is not counted by gitleaks.
    printf 'one\n' >"$work/repo/a.txt"
    commit_files
    status_is 0 scan_range --from "$clean" --to "$tip"
    status_is 2 scan_range --from "$base " --to "$clean"
    status_is 2 scan_range --from 1111111111111111111111111111111111111111 --to "$clean"
    status_is 2 scan_range --to bad-ref
    status_is 2 scan_range --from "$base"
    # A fake gitleaks that logs a git error, or scans nothing, and exits 0.
    mkdir -p "$work/bin"
    printf '#!/bin/sh\necho "1:00PM INF 0 commits scanned."\necho "1:00PM INF no leaks found"\n' >"$work/bin/gitleaks"
    chmod +x "$work/bin/gitleaks"
    PATH="$work/bin:$PATH" status_is 2 scan_range --from "$base" --to "$clean"
    printf '#!/bin/sh\necho "1:00PM ERR [git] fatal: bad revision"\necho "1:00PM INF 1 commits scanned."\n' >"$work/bin/gitleaks"
    PATH="$work/bin:$PATH" status_is 2 scan_range --from "$base" --to "$clean"
    # A path added by a merge commit is reported.
    main_branch="$(git -C "$work/repo" branch --show-current)"
    git -C "$work/repo" switch -q -c side
    printf 's\n' >"$work/repo/s.txt"
    commit_files
    side="$tip"
    git -C "$work/repo" switch -q "$main_branch"
    git -C "$work/repo" merge -q --no-ff --no-commit side >/dev/null 2>&1
    printf 'path: /%s/%s\n' home private-example >"$work/repo/merge.txt"
    commit_files
    status_is 1 scan_range --from "$side" --to "$tip"
    ;;
  *) fail "unknown regression case" ;;
esac
echo "ok - $1"
