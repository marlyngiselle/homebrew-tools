# ADR 0002. A reproducible source tarball that leaves out the formulae

Accepted on 2026-10-26.

## Context

Each formula pins its source with a `sha256`. Two problems follow when the formulae and the source share a repository.

1. If the tarball contained `Formula/`, writing the checksum into a formula would change the tarball, and with it the checksum. The loop never converges.
2. GitHub's automatic archives (`/archive/refs/tags/<tag>.tar.gz`) are generated on demand, and their bytes have changed in the past when GitHub changed its compression. A checksum that breaks without any change in this repository is a broken install for every user.

## Decision

The release workflow builds its own tarball with `scripts/build-tarball.sh` and attaches it to the GitHub release. The formulae point to that asset, never to an automatic archive.

| Choice | Effect |
| --- | --- |
| Only `tools/` and `LICENSE` are archived | Formula edits, docs and CI changes never change the bytes |
| `git archive` of the tree, not the commit | No pax header with the commit id |
| `--mtime` set to the last commit that touched `tools/` or `LICENSE` | File times depend on the tools, not on when the tag was made |
| `tar.umask=0022` and `core.autocrlf=false` forced on the command line | Local git configuration cannot change modes or line endings |
| gzip from Python with `mtime=0` | No timestamp or host OS byte in the gzip header, same output on macOS and Linux |

## Consequences

The checksum only moves when the tools move. A version's checksum can be computed before its tag exists, which is how the formulae for v0.1.0 were written, and CI can verify it afterwards (`tests.yml` rebuilds the tarball from the released tag and compares). The test suite asserts both properties. A commit that only touches `Formula/` keeps the bytes, and a commit under `tools/` changes them.

The cross-platform part of the guarantee rests on stock zlib producing the same deflate stream for the same input and level, which it has done for many releases. It is measured on macOS with two different Python builds, not yet on an Ubuntu runner. If it ever stopped holding, the release run would still be correct, because it computes the checksum from the tarball it uploads and rewrites the formulae with that value.
