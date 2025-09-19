# Commands

Collection of useful scripts/commands.

Scripts are made for Mac.

## Script Details

- **llm_copy.sh**  
    - Bundles allowed file types under provided paths into a single text file with headers.
    - Default behavior places the bundled file on the macOS clipboard; use `--string` to copy raw text instead.
    - Respects `.gitignore` when running inside a Git repository and skips hidden directories (eg `.git`, `.venv`).
    - Use `llm .` to copy the current directory.
    - Use `llm --string .` to copy as plain text.
    - Use `llm /dir_0/ /dir_1/ /dir_2/` to bundle specific directories.

- **llm_git_diff.sh**  
    - Generates a Git diff (with any standard `git diff` arguments) and places the resulting file on the macOS clipboard.
    - Accepts the repo root or any subdirectory as the first argument.
    - Supports flags like `--staged`, commit ranges, and path filters.
    - Leaves the temporary diff file on disk so you can paste it where needed.
    - Use `llm_diff .` (alias below) to capture the current repository's diff.

## External

- **Claude Code Monitor**
    - Realtime Claude Code Monitor
    - Requires: https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor

- **Claude Code Usage**
    - Historical Claude Code Usage
    - Requires: https://github.com/ryoppippi/ccusage

## Aliases/Commands

Suggest adding these as aliases (eg to `~/.bashrc`).

```
alias llm="~/llm_copy.sh"
alias llm_diff="~/llm_git_diff.sh"
alias ccm="claude-monitor"
alias ccu="npx --yes ccusage@latest"
```

Then can use:

```
cd /dir/of/interest/
llm .
llm_diff . --staged
```
