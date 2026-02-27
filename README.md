# commands

`commands` is a macOS first toolbox of small shell scripts for day to day developer work.

## Current status

This project is actively maintained for local developer workflows.

## What this project is trying to achieve

Keep common terminal tasks in one place as scripts you can run, inspect, and adapt.

## What you experience as a user

1. You run a script for a routine task.
2. The script handles repetitive steps with clear terminal output.
3. You can copy the script or add a shell alias for faster reuse.

## Requirements

- macOS shell environment (bash or zsh)
- core CLI tools used by individual scripts, for example `git`
- optional clipboard and notebook tooling used by specific scripts

## Quick start

1. Make scripts executable if needed.

```bash
chmod +x scripts/*.sh
```

2. Run scripts directly.

```bash
./scripts/llm_copy.sh .
./scripts/llm_git_diff.sh . --staged
```

3. Optional alias setup.

```bash
alias llm="$HOME/llm_copy.sh"
alias llm_diff="$HOME/llm_git_diff.sh"
alias clear_notebook_outputs="$HOME/clear_notebook_outputs.sh"
alias multitail="$HOME/multitail.sh"
alias ccm="claude-monitor"
alias ccu="npx --yes ccusage@latest"
```

4. Optional shell tab completion for script options.

```bash
# bash
source ./completions/commands.bash

# zsh
fpath=(./completions $fpath)
autoload -Uz compinit && compinit
```

## Script reference

### `llm_copy.sh`

Bundle allowed files into one text artifact for sharing with LLM tools.

- default mode copies a file reference to clipboard
- `--string` copies raw text content
- `--save-path` writes to an explicit output path
- respects `.gitignore` by default

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

Examples.

```bash
./scripts/llm_git_diff.sh . --staged
./scripts/llm_git_diff.sh . --exclude-untracked -- path/inside/repo
./scripts/llm_git_diff.sh . --string
```

### `git_commit_separate.sh`

Create one commit per changed file, including untracked and deleted files.

```bash
./scripts/git_commit_separate.sh --help
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

## External tools

- Claude Code Monitor: <https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor>
- Claude Code Usage: <https://github.com/ryoppippi/ccusage>

## Helpful tips

- Scripts print validation and error messages to stderr.
- Every script in `scripts/` supports `-h` and `--help`.
- Run from a clean shell if aliases or path overrides cause confusion.

## Known limitations

- Scripts are macOS-first and several commands rely on macOS clipboard tools.
- Some scripts assume Git repositories or local CLI tooling is already installed.
- Completion definitions are static and may need updates when script options change.

## Documentation map

- `README.md`: repository overview and usage examples
- `scripts/`: source of truth for command behavior
- `completions/`: optional shell completion definitions for script flags
- `docs/project-preferences.md`: durable project maintenance preferences
