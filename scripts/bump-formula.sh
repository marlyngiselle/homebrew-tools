#!/usr/bin/env bash
# Point one or more formulae at a new release tarball.
#
#   scripts/bump-formula.sh --version 0.2.0 --sha256 <sha> Formula/*.rb
#   scripts/bump-formula.sh --url <url> --sha256 <sha> Formula/portcheck.rb
#   scripts/bump-formula.sh --check --version 0.2.0 --sha256 <sha> Formula/*.rb
#
# For each formula it rewrites the top-level url and sha256 lines and drops
# the bottle block and any revision, because bottles built for the old
# version no longer match. Bottles for the new version are added by the
# release workflow.
#
# --version builds the url from REPO (default marlyngiselle/homebrew-tools).
# --check changes nothing and exits 1 if any formula would change.
# --dry-run prints a unified diff instead of writing.
# Idempotent: running it twice gives the same files.

set -euo pipefail

REPO="${REPO:-marlyngiselle/homebrew-tools}"

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'bump-formula: %s\n' "$*" >&2
  exit 64
}

URL="" SHA="" VERSION="" MODE="write"
FORMULAE=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url | --sha256 | --version)
      [ "$#" -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --url) URL="$2" ;;
        --sha256) SHA="$2" ;;
        --version) VERSION="${2#v}" ;;
      esac
      shift
      ;;
    --check) MODE="check" ;;
    --dry-run) MODE="dry-run" ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *) FORMULAE+=("$1") ;;
  esac
  shift
done

if [ -n "$VERSION" ]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must look like 1.2.3"
  [ -z "$URL" ] || die "pass --url or --version, not both"
  URL="https://github.com/$REPO/releases/download/v$VERSION/homebrew-tools-$VERSION.tar.gz"
fi
[ -n "$URL" ] || die "--url or --version is required"
[[ "$URL" =~ ^https://[^[:space:]\"]+\.tar\.gz$ ]] || die "--url must be an https URL to a .tar.gz"
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || die "--sha256 must be 64 lowercase hex characters"
[ "${#FORMULAE[@]}" -gt 0 ] || die "name at least one formula file"

changed=0
for f in "${FORMULAE[@]}"; do
  [ -f "$f" ] || die "no such formula: $f"
  grep -q '^  url "' "$f" || die "$f has no top-level url line"
  grep -q '^  sha256 "' "$f" || die "$f has no top-level sha256 line"

  tmp="$(mktemp "${TMPDIR:-/tmp}/bump.XXXXXX")"
  # Top-level stanzas are indented by exactly two spaces; the bottle block's
  # own sha256 lines are indented by four and are dropped with the block.
  awk -v url="$URL" -v sha="$SHA" '
    skip_blank && /^[[:space:]]*$/ { skip_blank = 0; next }
    { skip_blank = 0 }
    /^  bottle do[[:space:]]*$/ { in_bottle = 1; next }
    in_bottle {
      if ($0 ~ /^  end[[:space:]]*$/) { in_bottle = 0; skip_blank = 1 }
      next
    }
    /^  revision [0-9]+[[:space:]]*$/ { next }
    /^  url "/ { print "  url \"" url "\""; next }
    /^  sha256 "/ { print "  sha256 \"" sha "\""; next }
    { print }
  ' "$f" >"$tmp"

  if cmp -s "$f" "$tmp"; then
    rm -f "$tmp"
    printf 'unchanged  %s\n' "$f"
    continue
  fi
  changed=$((changed + 1))
  case "$MODE" in
    write)
      # Keep the original file mode; mv from mktemp would make it 0600.
      cat "$tmp" >"$f"
      rm -f "$tmp"
      printf 'updated    %s\n' "$f"
      ;;
    dry-run)
      diff -u "$f" "$tmp" | sed "1s|$tmp|$f (bumped)|" || true
      rm -f "$tmp"
      ;;
    check)
      rm -f "$tmp"
      printf 'outdated   %s\n' "$f"
      ;;
  esac
done

if [ "$MODE" = "check" ] && [ "$changed" -gt 0 ]; then
  exit 1
fi
exit 0
