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
