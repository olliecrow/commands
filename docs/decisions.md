# Decision Capture Policy

## Template
```
Decision:
Context:
Rationale:
Trade-offs:
Enforcement:
References:
```

## Recorded decisions

Decision: Default-branch-first day-to-day workflow is acceptable in this personal repo.
Context: This repository is part of the user's personal GitHub portfolio and often supports experimental or fast-iteration work. The user explicitly prefers to work directly on the default branch for normal day-to-day changes unless there is a task-specific reason to branch.
Rationale: Working directly on the default branch keeps personal-repo execution simple and fast. Branches remain available when they materially help with coordination, isolation, or review.
Trade-offs: There is less branch isolation by default, so targeted staging, small checkpoints, and verification still matter.
Enforcement: Agents may use the repository's default branch for normal personal-repo work unless the user requests a separate branch or the task clearly benefits from one.
References: `README.md`

Decision: This public repository keeps always-on public-readiness and safety/privacy/security discipline.
Context: The repository is currently public on GitHub and the user wants public personal repositories to continue following stronger public-surface safety, security, privacy, and publication standards during normal maintenance work.
Rationale: Public repositories have an external audience and external blast radius, so public-readiness hygiene should remain active continuously rather than only during one-off release work.
Trade-offs: Day-to-day maintenance carries more process overhead than it would in a private-only repo.
Enforcement: Keep public-surface safety, security, privacy, and publication checks active for normal maintenance work in this repository.
References: `README.md`

Decision: This personal repository uses only official, reputable, and well-supported third-party dependencies and services by default.
Context: The user explicitly does not want dodgy or non-reputable third-party services, APIs, MCPs, packages, frameworks, libraries, modules, or similar tooling introduced here, regardless of whether the repository is public or private.
Rationale: Favoring official vendor offerings and reputable, popular, well-supported dependencies reduces supply-chain, maintenance, abandonment, and trust risk while keeping the repository easier to maintain.
Trade-offs: Some niche or experimental tools will be skipped unless they later earn a stronger trust/support profile or the user explicitly approves them.
Enforcement: Prefer official APIs, official MCPs, official SDKs, and reputable well-maintained third-party services, packages, frameworks, libraries, and modules. Do not add obscure, weakly maintained, questionable, or low-trust dependencies or integrations without explicit user approval.
References: `docs/decisions.md`

Decision: Plain English and clear naming are the default for this repository.
Context:
The owner wants this repository to stay easy to understand in future chat sessions, docs work, code review, and day-to-day code changes.
Rationale:
Plain English cuts down confusion and makes work faster to read. Clear names in code reduce guessing and make the code easier to change safely later.
Trade-offs:
Some technical ideas need a short extra explanation, and some older names may stay in place until the code around them is touched safely.
Enforcement:
`AGENTS.md` requires plain English in chat and written project material. When touching code, prefer clear descriptive names for files, folders, flags, config keys, functions, classes, types, variables, tests, and examples, and rename confusing names when the change is safe and worth it.
References:
`AGENTS.md`

Decision:
Treat this repository as belonging under the personal GitHub account `olliecrow`.
Context:
Work in this workspace can span personal GitHub accounts and organization-owned repositories. A repo-level ownership note keeps docs, remotes, automation, releases, and publishing steps pointed at the right account.
Rationale:
A clear owner account rule cuts down avoidable confusion and keeps future repo work tied to the right GitHub home.
Trade-offs:
If this repository ever moves to a different owner, this note must be updated in the same change.
Enforcement:
`AGENTS.md` and any repo docs, remotes, automation, release, or publishing steps that need the owning GitHub account should point to `olliecrow` unless Ollie explicitly changes that ownership decision.
References:
`AGENTS.md`
