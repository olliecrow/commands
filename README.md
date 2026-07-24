# commands

`commands` is a macOS-first toolbox of small shell scripts for common developer tasks.

## Requirements

- macOS with Bash
- Git for the Git helpers
- Python 3 for `clear_notebook_outputs.sh`
- the built-in macOS clipboard tools for the LLM helpers

## Quick start

Run scripts directly from a clone of this repository.

```bash
./scripts/llm_copy.sh .
./scripts/llm_git_diff.sh . --staged
```

You can also add aliases that point to your clone.

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

## Script reference

### `llm_copy.sh`

Bundle allowed files into one text artifact for sharing with LLM tools.

- default mode copies a file reference to clipboard
- `--string` copies raw text content
- `--save-path` replaces the file at an explicit output path
- respects `.gitignore` by default
- excludes environment files from supported input

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

Examples.

```bash
./scripts/llm_git_diff.sh . --staged
./scripts/llm_git_diff.sh . --exclude-untracked -- path/inside/repo
./scripts/llm_git_diff.sh . --string
```

### `git_clean_branches.sh`

Prune remotes and delete local branches already merged into the default branch.

```bash
./scripts/git_clean_branches.sh --help
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

- Scripts are macOS-first and several commands rely on macOS clipboard tools.
- Some scripts assume Git repositories or local CLI tooling is already installed.
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

If `pre-commit` is installed, run its current-tree checks too.

```bash
pre-commit run --all-files
```
