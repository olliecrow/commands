Collection of useful scripts.

## Scripts

- **llm_copy.sh**  
  Concatenates allowed files under a given path and copies their contents to the clipboard.
  - Supports copying as plain text or as a file (macOS only).
  - Only copies a certain list of specified file types.
  - Ignores . directories (eg .git, .venv, etc)

## Usage

Suggest adding these as aliases.

eg to `~/.bashrc`

```
alias llm="~/llm-convert.sh"
```