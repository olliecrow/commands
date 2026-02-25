# commands

`commands` is a macOS-first toolbox of small shell utilities for day-to-day developer workflows.

## Project Aim

Keep frequently reused terminal tasks in one place as auditable scripts that are easy to run, copy, and modify.

## What This Repository Does

- packages practical utility scripts under `scripts/`
- focuses on repo-centric workflows (diff sharing, commit hygiene, branch cleanup)
- includes notebook and log helpers for recurring local operations

## Requirements

- macOS
- `bash`
- `git`
- `python3` (for notebook helper)
- macOS clipboard tools: `pbcopy`, `osascript`
- optional for `multitail.sh`: `pgrep`, `pkill`

## Quick Start

1. Make scripts executable (if needed):

```bash
chmod +x scripts/*.sh
```

2. Run scripts directly:

```bash
./scripts/llm_copy.sh .
./scripts/llm_git_diff.sh . --staged
```

3. Optional: create aliases in your shell profile:

```bash
alias llm="$HOME/llm_copy.sh"
alias llm_diff="$HOME/llm_git_diff.sh"
alias clear_notebook_outputs="$HOME/clear_notebook_outputs.sh"
alias multitail="$HOME/multitail.sh"
alias ccm="claude-monitor"
alias ccu="npx --yes ccusage@latest"
```

## Script Reference

### `llm_copy.sh`

Bundle allowed files into one text artifact for sharing with LLM tools.

- default mode copies a file reference to clipboard
- `--string` copies raw text content
- `--save-path` writes to an explicit output path
- respects `.gitignore` by default

Examples:

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

Examples:

```bash
./scripts/llm_git_diff.sh . --staged
./scripts/llm_git_diff.sh . --exclude-untracked -- path/inside/repo
./scripts/llm_git_diff.sh . --string
```

### `git_commit_separate.sh`

Create one commit per changed file (including untracked/deleted files).

### `git_clean_branches.sh`

Prune remotes and delete local branches already merged into the default branch.

### `clear_notebook_outputs.sh`

Clear Jupyter notebook outputs recursively without changing code/markdown cells.

### `multitail.sh`

Tail all regular files in a directory and automatically include newly created files.

## External Tools

- Claude Code Monitor: <https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor>
- Claude Code Usage: <https://github.com/ryoppippi/ccusage>

## Logging and Debugging

- scripts print validation and error messages to stderr
- use `-h/--help` where supported for usage details
- run from a clean shell if aliases/path overrides cause unexpected behavior

## Documentation Map

- `README.md`: repository overview and usage examples
- `scripts/`: source of truth for command behavior
