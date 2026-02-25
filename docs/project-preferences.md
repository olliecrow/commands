# Project Preferences (Going Forward)

These preferences define how `commands` should be maintained as an open-source-ready toolbox.

## Quality and Scope

- Keep scripts small, readable, and focused on one clear task.
- Prefer explicit behavior and predictable flags over hidden side effects.
- Avoid host-specific assumptions unless clearly documented.

## Security and Confidentiality

- Never commit secrets, credentials, tokens, API keys, or private key material.
- Never commit private/sensitive machine paths; use placeholders such as `/path/to/project`, `/Users/YOU`, `/home/user`, or `C:\\Users\\USERNAME`.
- Keep local runtime state untracked (`.env*`, `.claude/`, `.codex/`, temp artifacts).
- If sensitive data is found in history, rotate credentials and scrub history before publication.

## Documentation Expectations

- Keep `README.md` and script help text in sync with real behavior.
- Document prerequisites and edge cases for scripts that can modify git state.

## Verification Expectations

- Smoke-test changed scripts with realistic inputs before merge.
- Confirm failure modes are clear and non-destructive by default.

## Collaboration Preferences

- Preserve accurate author/committer attribution for each contributor.
- Avoid destructive history rewrites unless required for secret/confidentiality remediation.
