# ADR 0001. Tools and formulae in one repository

Accepted on 2026-10-26.

## Context

A tap usually contains only formulae, and each formula downloads software that lives in its own repository. The tools in this tap are small. Each one is a script, a man page and a test suite. Giving every tool its own repository, release pipeline and version would triple the maintenance for no benefit to users.

## Decision

The tools live in `tools/<name>/`, next to `Formula/`, in the tap repository. One tag releases all of them, from one source tarball, under one version number.

## Consequences

| Gain | Cost |
| --- | --- |
| A change to a tool, its tests and its formula is one pull request | Every formula moves to the new version on every release, even if its tool did not change |
| One pipeline, one set of pinned actions, one place to audit | `brew upgrade` reinstalls tools whose code is identical to the previous version |
| The tap is self-contained and testable from a single clone | A new formula cannot pass `brew test-bot` until a release contains its tool (documented in [adding-a-formula.md](../adding-a-formula.md)) |

If a tool grows past a single script or needs its own cadence, it moves to its own repository and its formula keeps working by pointing to that repository's releases.
