#!/usr/bin/env bats
# Tests for the release scripts: the formula bump and the reproducible
# source tarball. Each test works on copies in a temporary directory.

setup() {
  SCRIPTS="$BATS_TEST_DIRNAME/../scripts"
  SHA_A="$(printf 'a%.0s' {1..64})"
  SHA_B="$(printf 'b%.0s' {1..64})"
  F="$BATS_TEST_TMPDIR/sample.rb"
  cat >"$F" <<'RUBY'
class Sample < Formula
  desc "Sample"
  homepage "https://example.com"
  url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.1.0/homebrew-tools-0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  revision 2

  bottle do
    root_url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.1.0"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "1111111111111111111111111111111111111111111111111111111111111111"
  end

  def install
    bin.install "sample"
  end
end
RUBY
}

# ---------------------------------------------------------------- bump

@test "bump: --version derives the release URL and sets the checksum" {
  run "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == "updated    $F" ]]
  grep -q '^  url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.2.0/homebrew-tools-0.2.0.tar.gz"$' "$F"
  grep -q "^  sha256 \"$SHA_A\"$" "$F"
}

@test "bump: drops the stale bottle block and revision, keeps the rest" {
  "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$F"
  ! grep -q 'bottle do' "$F"
  ! grep -q 'cellar:' "$F"
  ! grep -q 'revision' "$F"
  grep -q '^  license "MIT"$' "$F"
  grep -q '^  def install$' "$F"
  # No double blank line where the bottle block used to be.
  ! awk 'prev == "" && $0 == "" { found = 1 } { prev = $0 } END { exit !found }' "$F"
}

@test "bump: the result is still valid Ruby" {
  command -v ruby >/dev/null || skip "ruby not installed"
  "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$F"
  ruby -c "$F"
}

@test "bump: is idempotent" {
  "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$F"
  cp "$F" "$BATS_TEST_TMPDIR/first.rb"
  run "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$F"
  [[ "$output" == "unchanged  $F" ]]
  cmp "$F" "$BATS_TEST_TMPDIR/first.rb"
}

@test "bump: keeps the file mode" {
  chmod 644 "$F"
  "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$F"
  [ -r "$F" ]
  ls -l "$F" | grep -q '^-rw-r--r--'
}

@test "bump: --check reports drift without writing" {
  cp "$F" "$BATS_TEST_TMPDIR/orig.rb"
  run "$SCRIPTS/bump-formula.sh" --check --version 0.2.0 --sha256 "$SHA_B" "$F"
  [ "$status" -eq 1 ]
  [[ "$output" == "outdated   $F" ]]
  cmp "$F" "$BATS_TEST_TMPDIR/orig.rb"
  "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_B" "$F"
  run "$SCRIPTS/bump-formula.sh" --check --version 0.2.0 --sha256 "$SHA_B" "$F"
  [ "$status" -eq 0 ]
}

@test "bump: --dry-run prints a diff and writes nothing" {
  cp "$F" "$BATS_TEST_TMPDIR/orig.rb"
  run "$SCRIPTS/bump-formula.sh" --dry-run --version 0.2.0 --sha256 "$SHA_A" "$F"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+  sha256 \"$SHA_A\""* ]]
  [[ "$output" == *"-  bottle do"* ]]
  cmp "$F" "$BATS_TEST_TMPDIR/orig.rb"
}

@test "bump: --url is used verbatim" {
  run "$SCRIPTS/bump-formula.sh" --url https://example.com/x-1.0.0.tar.gz --sha256 "$SHA_A" "$F"
  [ "$status" -eq 0 ]
  grep -q '^  url "https://example.com/x-1.0.0.tar.gz"$' "$F"
}

@test "bump: rejects bad input before touching anything" {
  cp "$F" "$BATS_TEST_TMPDIR/orig.rb"
  run "$SCRIPTS/bump-formula.sh" --version 0.2 --sha256 "$SHA_A" "$F"
  [ "$status" -eq 64 ]
  run "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 ABC "$F"
  [ "$status" -eq 64 ]
  run "$SCRIPTS/bump-formula.sh" --url http://example.com/x.tar.gz --sha256 "$SHA_A" "$F"
  [ "$status" -eq 64 ]
  run "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A"
  [ "$status" -eq 64 ]
  run "$SCRIPTS/bump-formula.sh" --version 0.2.0 --sha256 "$SHA_A" "$BATS_TEST_TMPDIR/missing.rb"
  [ "$status" -eq 64 ]
  cmp "$F" "$BATS_TEST_TMPDIR/orig.rb"
}

@test "bump: every formula in the tap is bumpable" {
  for f in "$BATS_TEST_DIRNAME"/../Formula/*.rb; do
    cp "$f" "$BATS_TEST_TMPDIR/"
    run "$SCRIPTS/bump-formula.sh" --check --version 9.9.9 --sha256 "$SHA_A" "$BATS_TEST_TMPDIR/$(basename "$f")"
    [ "$status" -eq 1 ]
  done
}

# ---------------------------------------------------------------- tarball

make_repo() {
  REPO_DIR="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO_DIR/tools/demo" "$REPO_DIR/scripts" "$REPO_DIR/Formula"
  cp "$SCRIPTS/build-tarball.sh" "$REPO_DIR/scripts/"
  printf 'MIT\n' >"$REPO_DIR/LICENSE"
  printf '#!/bin/sh\necho demo\n' >"$REPO_DIR/tools/demo/demo"
  chmod +x "$REPO_DIR/tools/demo/demo"
  printf 'class Demo < Formula\nend\n' >"$REPO_DIR/Formula/demo.rb"
  git -C "$REPO_DIR" init -q -b main
  git -C "$REPO_DIR" -c user.name=t -c user.email=t@example.com add -A
  GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" \
    git -C "$REPO_DIR" -c user.name=t -c user.email=t@example.com commit -q -m init
}

build() {
  (cd "$REPO_DIR" && scripts/build-tarball.sh "$@") | awk '{ print $1 }'
}

@test "tarball: holds tools/ and LICENSE under a versioned prefix, never Formula/" {
  command -v python3 >/dev/null || skip "python3 not installed"
  make_repo
  build 0.1.0 >/dev/null
  run tar -tzf "$REPO_DIR/dist/homebrew-tools-0.1.0.tar.gz"
  [[ "$output" == *"homebrew-tools-0.1.0/LICENSE"* ]]
  [[ "$output" == *"homebrew-tools-0.1.0/tools/demo/demo"* ]]
  [[ "$output" != *"Formula"* ]]
  [[ "$output" != *"scripts"* ]]
}

@test "tarball: writes a .sha256 file that matches" {
  command -v python3 >/dev/null || skip "python3 not installed"
  make_repo
  sum="$(build 0.1.0)"
  [[ "$sum" =~ ^[0-9a-f]{64}$ ]]
  [ "$(awk '{ print $1 }' "$REPO_DIR/dist/homebrew-tools-0.1.0.tar.gz.sha256")" = "$sum" ]
}

@test "tarball: a commit that only touches Formula/ keeps the same bytes" {
  command -v python3 >/dev/null || skip "python3 not installed"
  make_repo
  first="$(build 0.1.0)"
  printf '  # bumped\n' >>"$REPO_DIR/Formula/demo.rb"
  git -C "$REPO_DIR" -c user.name=t -c user.email=t@example.com commit -q -am bump
  second="$(build 0.1.0)"
  [ "$first" = "$second" ]
}

@test "tarball: a change under tools/ changes the bytes" {
  command -v python3 >/dev/null || skip "python3 not installed"
  make_repo
  first="$(build 0.1.0)"
  printf 'echo more\n' >>"$REPO_DIR/tools/demo/demo"
  git -C "$REPO_DIR" -c user.name=t -c user.email=t@example.com commit -q -am change
  second="$(build 0.1.0)"
  [ "$first" != "$second" ]
}

@test "tarball: REF builds an older commit" {
  command -v python3 >/dev/null || skip "python3 not installed"
  make_repo
  first="$(build 0.1.0)"
  printf 'echo more\n' >>"$REPO_DIR/tools/demo/demo"
  git -C "$REPO_DIR" -c user.name=t -c user.email=t@example.com commit -q -am change
  again="$(cd "$REPO_DIR" && REF=HEAD~1 scripts/build-tarball.sh 0.1.0 | awk '{ print $1 }')"
  [ "$first" = "$again" ]
}

@test "tarball: rejects a malformed version" {
  make_repo
  run bash -c "cd '$REPO_DIR' && scripts/build-tarball.sh 1.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERSION must look like 1.2.3"* ]]
}
