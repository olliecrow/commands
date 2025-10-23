#!/bin/bash
# Clear Jupyter notebook execution artifacts under provided paths.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: clear_notebook_outputs.sh <path> [path ...]

Recursively finds .ipynb files under each path and removes all cell outputs
while retaining the original code and markdown content. Directories are scanned
recursively; individual notebook files are also accepted.

Examples:
  clear_notebook_outputs.sh notebooks/
  clear_notebook_outputs.sh notebook.ipynb another_dir/
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

need_cmd python3

python3 - "$@" <<'PY'
import json
import sys
from pathlib import Path

paths = [Path(arg).expanduser() for arg in sys.argv[1:]]
if not paths:
    print("Error: path argument required", file=sys.stderr)
    sys.exit(1)

cwd = Path.cwd()
seen = set()
notebooks = []

for root in paths:
    if not root.exists():
        print(f"Warning: '{root}' does not exist; skipping", file=sys.stderr)
        continue
    if root.is_file():
        if root.suffix.lower() == ".ipynb":
            resolved = root.resolve()
            if resolved not in seen:
                seen.add(resolved)
                notebooks.append(resolved)
        else:
            print(f"Warning: '{root}' is not a .ipynb file; skipping", file=sys.stderr)
    elif root.is_dir():
        for nb in sorted(root.rglob("*.ipynb")):
            if any(part == ".ipynb_checkpoints" for part in nb.parts):
                continue
            resolved = nb.resolve()
            if resolved not in seen:
                seen.add(resolved)
                notebooks.append(resolved)
    else:
        print(f"Warning: '{root}' is not a file or directory; skipping", file=sys.stderr)

if not notebooks:
    print("No notebooks found.")
    sys.exit(0)

failures = False
cleared = 0

def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(cwd))
    except ValueError:
        return str(path)

for nb in notebooks:
    pretty = display_path(nb)
    try:
        raw = nb.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"Error: failed to read {pretty}: {exc}", file=sys.stderr)
        failures = True
        continue

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid notebook JSON in {pretty}: {exc}", file=sys.stderr)
        failures = True
        continue

    changed = False
    for cell in data.get("cells", []):
        if cell.get("cell_type") == "code":
            if "outputs" in cell:
                if cell["outputs"]:
                    cell["outputs"] = []
                    changed = True
            else:
                cell["outputs"] = []
                changed = True
        if "execution_count" in cell and cell["execution_count"] is not None:
            cell["execution_count"] = None
            changed = True

    if not changed:
        print(f"No changes needed: {pretty}")
        continue

    try:
        text = json.dumps(data, indent=1, ensure_ascii=False)
        if not text.endswith("\n"):
            text += "\n"
        nb.write_text(text, encoding="utf-8")
    except OSError as exc:
        print(f"Error: failed to write {pretty}: {exc}", file=sys.stderr)
        failures = True
        continue

    cleared += 1
    print(f"Cleared outputs: {pretty}")

print(f"Processed {len(notebooks)} notebook(s); cleared outputs from {cleared}.")
if failures:
    sys.exit(1)
PY
