# Scripts

Collection of useful scripts.

## Script Details

- **llm_copy.sh**  
  Concatenates allowed files under a given path and copies their contents to the clipboard.
  - Supports copying as plain text or as a file (macOS only).
  - Only copies a certain list of specified file types.
  - Ignores . directories (eg .git, .venv, etc).
  - Use `llm .` to copy to clipboard as test.
  - Use `llm --file .` to copy to clipboard as file.
  - Use `llm /dir_0/ /dir_1/ /dir_2/` to copy specific dirs.

## Usage

Suggest adding these as aliases.

eg to `~/.bashrc`

```
alias llm="~/llm-convert.sh"
```

Then can use:

```
cd /dir/of/interest/
llm .
```