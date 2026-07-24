# Project Decisions

## Work on the default branch

**Decision:** Normal maintenance may happen directly on `main`.

This is a personal repository with a fast day-to-day workflow. A separate branch is still useful when a change needs isolation, coordination, or review. Direct work on `main` makes careful staging more important, so commits must capture coherent outcomes rather than arbitrary file groups.

Enforced in `AGENTS.md`.

## Keep the repository ready for public viewing

**Decision:** Apply public safety, privacy, security, and publication checks during normal maintenance.

The repository is public, so every tracked file and outgoing commit has an external audience. Keeping the checks active at all times is safer than treating publication as a separate release step.

Enforced in `AGENTS.md`, `.pre-commit-config.yaml`, and `.github/workflows/security-policy.yml`.

## Prefer trusted dependencies

**Decision:** Use official, reputable, maintained, and well-supported dependencies by default.

This reduces supply-chain and abandonment risk. A niche dependency may still be suitable when there is a concrete need and enough evidence to review it.

Enforced in `AGENTS.md`.

## Use plain English and clear names

**Decision:** Plain English and descriptive names are the default.

This keeps scripts, docs, reviews, and future maintenance easy to understand. Some technical terms still need a short explanation, and established names should change only when the benefit is clear and the risk is low.

Enforced in `AGENTS.md`.

## Keep personal ownership explicit

**Decision:** This repository belongs under the personal GitHub account `olliecrow`.

The workspace can contain repositories with different owners. An explicit rule keeps remotes, automation, releases, and publishing pointed at the right account. Update the rule in the same change if ownership ever moves.

Enforced in `AGENTS.md`.
