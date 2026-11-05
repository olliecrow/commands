# commands

`commands` is a macOS-first toolbox of small shell scripts for common developer tasks.

## Requirements

- Bash 3.2 or newer (the macOS `/bin/bash` works) on macOS or Linux
- Git for the Git helpers
- Python 3.8 or newer for `clear_notebook_outputs.sh`
- for the LLM helpers: `pbcopy` for `--string`, `osascript` for the default
  file-on-clipboard mode (both are built into macOS). `--save-path` works
  without either tool, so on Linux use `--save-path`.

## Quick start

Run scripts directly from a clone of this repository.

```bash
./scripts/llm_copy.sh .
./scripts/llm_git_diff.sh . --staged
```

You can also add aliases that point to your clone.
Note that `multitail` below is this repo's script, not the separate
`multitail` program; the alias hides that program if it is installed.

```bash
alias llm="/path/to/commands/scripts/llm_copy.sh"
alias llm_diff="/path/to/commands/scripts/llm_git_diff.sh"
alias clear_notebook_outputs="/path/to/commands/scripts/clear_notebook_outputs.sh"
alias multitail="/path/to/commands/scripts/multitail.sh"
```

Optional shell completion is available for Bash and zsh.

```bash
# bash
source ./completions/commands.bash

# zsh
fpath=(./completions $fpath)
autoload -Uz compinit && compinit
```

Bash completion requires
[bash-completion](https://github.com/scop/bash-completion).
Completion is bound to the script file names (such as `llm_copy.sh`),
not to aliases.

## Script reference

### `llm_copy.sh`

Bundle allowed files into one text artifact for sharing with LLM tools.

- default mode copies a file reference to clipboard
- `--string` copies raw text content
- `--save-path` replaces the file at an explicit output path
- respects `.gitignore` by default (`--ignore-gitignore` turns this off)
- includes only the file extensions and names listed in `--help`
- skips paths with a hidden part (a name that starts with `.`), such as `.env`
- skips secret-like names without regard to case: `*secret*`, `*credential*`,
  `*.pem`, `*.key`, SSH private-key names, `.env*`, and `aws.ini`
- skips a file that contains a credential-like assignment, a private-key
  header, or a GitHub, AWS, or OpenAI-style key (including project keys),
  and prints that file's name. The rest of the bundle is still copied
- `--allow-sensitive` overrides secret-name and content checks; the normal
  file type and hidden-path rules still apply

Examples.

```bash
./scripts/llm_copy.sh .
./scripts/llm_copy.sh --string .
./scripts/llm_copy.sh . --save-path /tmp/bundle.txt
```

### `llm_git_diff.sh`

Generate a git diff and copy either the file artifact or plain text to clipboard.

- accepts standard `git diff` args
- includes untracked files by default
- use `--exclude-untracked` to skip untracked files
- leaves the repository index unchanged
- does not run external diff drivers from the Git config

Examples.

```bash
./scripts/llm_git_diff.sh . --staged
./scripts/llm_git_diff.sh . --exclude-untracked -- path/inside/repo
./scripts/llm_git_diff.sh . --string
```

### `git_clean_branches.sh`

Fetch with `--prune` (this removes remote-tracking refs for branches deleted
on the remote), then delete local branches already merged into the default
branch. It never force-deletes, and keeps the current branch and branches
checked out in other worktrees.

```bash
./scripts/git_clean_branches.sh --dry-run   # list only; no fetch or delete
./scripts/git_clean_branches.sh
```

### `clear_notebook_outputs.sh`

Clear Jupyter notebook outputs recursively without changing code or markdown cells.

### `multitail.sh`

Tail all regular files in a directory and include newly created files.

## Helpful tips

- Scripts print validation and error messages to stderr.
- Every user-facing script supports `-h` and `--help`.
- Run from a clean shell if aliases or path overrides cause confusion.

## Known limitations

- The clipboard modes of the LLM helpers work on macOS only.
- Completion definitions are static and may need updates when script options change.

## Documentation map

- `README.md`: repository overview and usage examples
- `scripts/`: source of truth for command behavior
- `completions/`: optional shell completion definitions for script flags
- `AGENTS.md`: repository maintenance rules
- `docs/decisions.md`: durable project decisions and reasons
- `SECURITY.md`: private vulnerability reporting

## Development

Run the behavior tests before sending a change.

```bash
bash tests/run.sh
```

If `pre-commit` is installed, install its hooks (they also scan each push
for secrets and local paths) and run its current-tree checks.

```bash
pre-commit install
pre-commit run --all-files
```
