# Scripts

Collection of useful scripts.

Scripts are made for Mac.

## Script Details

- **llm_copy.sh**  
    - Concatenates allowed files under a given path and copies their contents to the clipboard.
    - Supports copying as plain text or as a file (macOS only).
    - Only copies a certain list of specified file types.
    - Ignores . directories (eg .git, .venv, etc).
    - Use `llm .` to copy to clipboard as test.
    - Use `llm --file .` to copy to clipboard as file.
    - Use `llm /dir_0/ /dir_1/ /dir_2/` to copy specific dirs.

- **Claude Code Monitor**
    - Realtime Claude Code Monitor
    - https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor

- **Claude Code Usage**
    - Historical Claude Code Usage
    - https://github.com/ryoppippi/ccusage

## Aliases

Suggest adding these as aliases (eg to `~/.bashrc`).

```
alias llm="~/llm_copy.sh"
alias ccm="claude-monitor"
alias ccu="npx --yes ccusage@latest"
```

Then can use:

```
cd /dir/of/interest/
llm .
```