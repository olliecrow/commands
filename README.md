# Commands

Collection of useful scripts/commands.

Scripts are made for Mac.

## Script Details

- **llm_copy.sh**  
    - Bundles allowed file types under provided paths into a single text file with headers.
    - Default behavior places the bundled file on the macOS clipboard; use `--string` to copy raw text instead.
    - Optional: `--save-path <file>` to save the bundle at a specific path. In file mode, that file is also placed on the clipboard; in string mode, the text is copied and written to the file.
    - Respects `.gitignore` when running inside a Git repository and skips hidden directories (eg `.git`, `.venv`). Pass `--ignore_gitignore` (or `--ignore-gitignore`) to include ignored files when needed.
    - Use `llm .` to copy the current directory.
    - Use `llm --string .` to copy as plain text.
    - Use `llm . --save-path /tmp/bundle.txt` to save and also place the file on the clipboard.
    - Use `llm --string . --save-path=/tmp/bundle.txt` to save and copy the text content.
    - Use `llm /dir_0/ /dir_1/ /dir_2/` to bundle specific directories.

- **llm_git_diff.sh**  
    - Generates a Git diff (with any standard `git diff` arguments) and places the resulting file on the macOS clipboard.
    - Accepts the repo root or any subdirectory as the first argument.
    - Supports flags like `--staged`, commit ranges, and path filters.
    - Optional: `--save-path <file>` to write the diff to a specific file (which is also placed on the clipboard).
    - Includes untracked files by default (respects `.gitignore`). Use `--exclude-untracked` to skip them; internally the script uses `git add -N` and resets on exit. If you provide a pathspec after `--`, untracked detection is limited to that path.
    - Leaves the temporary diff file on disk so you can paste it where needed.
    - Use `llm_diff .` (alias below) to capture the current repository's diff.
    - Examples:
        - `llm_diff . --staged`
        - `llm_diff . --exclude-untracked` (skip untracked files)
        - `llm_diff . --exclude-untracked -- path/inside/repo`
        - `llm_diff . --save-path /tmp/diff.txt`
    - Note: script-specific options (like `--save-path`, `--exclude-untracked`) should appear before a standalone `--` that introduces a pathspec.

- **git_commit_separate.sh**  
    - Creates one commit per changed item (tracked + untracked, including deletions).
    - Unstages current changes first (does not discard work) when `HEAD` exists.
    - Handles renames/copies as a single commit by staging old+new together.
    - Expands untracked directories to individual files (`-uall`).
    - Skips empty commits and uses the message `Updated: <path>.`
    - Usage: `git_commit_separate.sh` (run inside a Git repo)

- **clear_notebook_outputs.sh**  
    - Recursively clears all cell outputs from Jupyter notebooks under the provided path(s) without altering code or markdown cells.
    - Accepts directories or individual notebook files and skips `.ipynb_checkpoints` directories.
    - Requires: `python3`
    - Examples:
        - `clear_notebook_outputs.sh notebooks/`
        - `clear_notebook_outputs.sh notebook.ipynb another_dir/`

- **multitail.sh**  
    - Watches every regular file in a directory and starts a `tail -n0 -F` session for each one.
    - Polls every second so new files are tailed automatically without restarting the command.
    - Ensures only one tail process runs per file and cleans them up when you exit.
    - Usage: `multitail <directory>` (directory argument required)
    - Example: `multitail /var/log/my-service`
    - Help: `multitail -h`
    - Requires: `tail`, `pgrep`, `pkill`

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
alias clear_notebook_outputs="~/clear_notebook_outputs.sh"
alias multitail="~/multitail.sh"
alias ccm="claude-monitor"
alias ccu="npx --yes ccusage@latest"
```

Then can use:

```
cd /dir/of/interest/
llm .
llm_diff . --staged
```
