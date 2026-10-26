# ADR 0003. Tag-driven release that ends in a pull request

Accepted on 2026-10-26.

## Context

The template from `brew tap-new` publishes bottles with `brew pr-pull`. A pull request changes a formula, CI builds bottles, and a maintainer runs `brew pr-pull` to upload them and push the bottle commit straight to `main`. In this tap the version is not decided by an outside project but by this repository, and three formulae change together on every release.

## Decision

A semantic version tag on `main` starts `release.yml`. It builds the tarball, creates the release, builds bottles with `brew test-bot`, uploads them with `brew pr-upload`, and opens a pull request with the new `url`, `sha256` and bottle blocks. Nothing is pushed to `main` by automation.

| Option | Why not |
| --- | --- |
| `brew pr-pull` on every pull request | The tarball for the new version does not exist until a tag does, so pull request bottles would be built from the previous release |
| Release workflow pushes straight to `main` | Needs a bypass of branch protection and removes the last human check before users get the change |
| Bottles on GitHub Packages (ghcr.io) | Works, but splits a release across two places. Release assets keep the tarball, its checksum and the bottles together |
| No bottles at all | Simpler, but then nothing proves the formula installs on a clean Mac before users try |

## Consequences

Least privilege per job. Only `source` and `publish` can write, and `publish` runs in the `release` environment, which can require an approval. The pull request opened with `GITHUB_TOKEN` does not trigger `tests.yml` by itself. The release run already ran the same `brew test-bot` steps on the same formulae, and [release-process.md](../release-process.md) explains how to get the checks on the pull request too.
