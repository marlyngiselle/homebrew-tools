#!/usr/bin/env bash
# Build the release source tarball, reproducibly.
#
#   scripts/build-tarball.sh VERSION [OUTDIR]
#
# The tarball holds tools/ and LICENSE only. Formula/ is left out on
# purpose: the formulae carry the tarball's sha256, so including them would
# make the checksum depend on itself (see docs/adr/0002).
#
# Same tree in, same bytes out: file times are pinned to the last commit
# that touched tools/ or LICENSE, git normalises owners and modes, and gzip
# runs with a zero timestamp. Prints "<sha256>  <path>" on stdout.
#
# Environment: REF (default HEAD), the commit or tag to archive.

set -euo pipefail

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'build-tarball: %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") die "VERSION is required, for example 0.1.0 (see --help)" ;;
esac

VERSION="${1#v}"
OUTDIR="${2:-dist}"
REF="${REF:-HEAD}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 1.2.3, got '$1'"
command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required (used for a portable, timestamp-free gzip)"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || die "unknown ref: $REF"

NAME="homebrew-tools-$VERSION"
mkdir -p "$OUTDIR"
OUT="$OUTDIR/$NAME.tar.gz"

# Archive the tree, not the commit: a commit adds a pax header with its id,
# which would change the bytes on every release even when tools/ did not.
EPOCH="$(git log -1 --format=%ct "$REF" -- tools LICENSE)"
[ -n "$EPOCH" ] || die "no commit touches tools/ or LICENSE at $REF"

# Pin the settings that change archive bytes, whatever the local git config.
git -c tar.umask=0022 -c core.autocrlf=false archive --format=tar --prefix="$NAME/" --mtime="@$EPOCH" "$REF^{tree}" tools LICENSE |
  python3 -c 'import gzip, sys; sys.stdout.buffer.write(gzip.compress(sys.stdin.buffer.read(), compresslevel=9, mtime=0))' \
    >"$OUT"

if command -v sha256sum >/dev/null 2>&1; then
  SUM="$(sha256sum "$OUT" | awk '{ print $1 }')"
else
  SUM="$(shasum -a 256 "$OUT" | awk '{ print $1 }')"
fi
printf '%s  %s\n' "$SUM" "$NAME.tar.gz" >"$OUT.sha256"
printf '%s  %s\n' "$SUM" "$OUT"
