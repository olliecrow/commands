# Repository Guidelines

## Repository Ownership

- This repository belongs under the personal GitHub account `olliecrow`.
- Do not move it to a GitHub organization or a different personal account unless Ollie explicitly asks for that change.
- When docs, remotes, automation, releases, or publishing steps need the owning GitHub account, use `olliecrow`.

## Public Repository Safety

- Treat every tracked file, commit, issue, pull request, and CI log as public.
- Never add secrets, private account details, or local machine paths.
- Before pushing, inspect the exact outgoing range for private data, unintended files, unsuitable messages, and licence or attribution problems.
- Keep security checks in `.pre-commit-config.yaml` and `.github/workflows/security-policy.yml` passing.

## Code and Scope

- Keep each user-facing script small and focused on one task.
- Prefer explicit behavior, clear flags, and direct names.
- Preserve user work. Scripts must not silently discard or commit unrelated changes.
- Keep `README.md`, completions, and help text in sync with script behavior.
- Remove obsolete commands and docs instead of maintaining parallel paths.

## Workflow

- Normal maintenance may happen directly on `main`.
- Make coherent commits by outcome. Do not split commits only because files differ.
- Run `tests/run.sh` and the applicable configured hooks before committing or pushing.

## Dependencies

- Prefer built-in platform tools and existing dependencies.
- Add third-party code only when there is a concrete need and the source is official, reputable, maintained, and licence-compatible.
- Pin CI dependencies to an exact reviewed version.

## Plain English Default

- Use plain English in chat, session replies, docs, notes, comments, reports, commit messages, issue text, and review text.
- Prefer short words, short sentences, and direct statements.
- If a technical term is needed for correctness, explain it in simple words the first time.
- In code, prefer clear descriptive names for files, folders, flags, config keys, functions, classes, types, variables, tests, and examples.
- Avoid vague names, short cryptic names, and cute internal code names unless an old established name is already clearer than changing it.
- When touching old code, rename confusing names if the change is low risk and clearly improves readability.
- Keep the durable why for this rule in `docs/decisions.md`.
