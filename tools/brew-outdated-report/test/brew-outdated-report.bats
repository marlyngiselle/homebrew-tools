#!/usr/bin/env bats
# Tests for brew-outdated-report. brew is a stub that replays a fixture,
# and SOURCE_DATE_EPOCH pins the timestamp so whole reports can be compared.

setup() {
  TOOL="$BATS_TEST_DIRNAME/../brew-outdated-report"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  export STUB_LOG="$BATS_TEST_TMPDIR/brew.log"
  export BREW_FIXTURE="$FIXTURES/outdated.json"
  export SOURCE_DATE_EPOCH=1767225600
  : >"$STUB_LOG"
  PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

@test "--version and --help" {
  run "$TOOL" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-outdated-report "* ]]
  run "$TOOL" --help
  [[ "$output" == *"--fail-on-outdated"* ]]
}

@test "runs brew outdated --json=v2 without auto-update by default" {
  run "$TOOL"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "outdated --json=v2" ]
  [ "$(cat "$STUB_LOG.env")" = "1" ]
}

@test "--greedy is passed through to brew" {
  run "$TOOL" --greedy
  [ "$(cat "$STUB_LOG")" = "outdated --json=v2 --greedy" ]
}

@test "--input reads a file and never calls brew" {
  run "$TOOL" --input "$FIXTURES/outdated.json"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "--input - reads stdin" {
  run bash -c "'$TOOL' --input - <'$FIXTURES/empty.json'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Everything is up to date."* ]]
}

@test "the timestamp honours SOURCE_DATE_EPOCH" {
  run "$TOOL"
  [ "${lines[1]}" = "Generated 2026-01-01T00:00:00Z by brew-outdated-report dev." ]
}

@test "summary counts formulae, casks, majors and pins" {
  run "$TOOL"
  [[ "$output" == *"| Outdated formulae | 5 |"* ]]
  [[ "$output" == *"| Outdated casks | 1 |"* ]]
  [[ "$output" == *"| Major upgrades | 1 |"* ]]
  [[ "$output" == *"| Pinned, held back | 1 |"* ]]
}

@test "each change is classified, and a _N suffix is a rebuild" {
  run "$TOOL"
  [[ "$output" == *'| `node` | 22.9.0 | 24.1.0 | major | no |'* ]]
  [[ "$output" == *'| `git` | 2.47.0 | 2.48.1 | minor | no |'* ]]
  [[ "$output" == *'| `zstd` | 1.5.6 | 1.5.7 | patch | no |'* ]]
  [[ "$output" == *'| `jq` | 1.7.1 | 1.7.1_1 | rebuild | no |'* ]]
}

@test "rows are sorted by severity, then by name" {
  run "$TOOL"
  order="$(printf '%s\n' "$output" | awk -F'`' '/^\| `/ { print $2 }' | head -5 | tr '\n' ' ')"
  [ "$order" = "node git postgresql@16 zstd jq " ]
}

@test "pinned formulae are excluded from the upgrade command" {
  run "$TOOL"
  [[ "$output" == *"brew upgrade node git zstd jq"* ]]
  [[ "$output" == *"brew upgrade --cask visual-studio-code"* ]]
  [[ "$output" == *'brew unpin <name>'* ]]
}

@test "an empty result says so and keeps valid tables" {
  export BREW_FIXTURE="$FIXTURES/empty.json"
  run "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Outdated formulae | 0 |"* ]]
  [[ "$output" == *"Nothing outdated."* ]]
  [[ "$output" == *"Everything is up to date."* ]]
}

@test "--fail-on-outdated exits 1 only when something is outdated" {
  run "$TOOL" --fail-on-outdated
  [ "$status" -eq 1 ]
  export BREW_FIXTURE="$FIXTURES/empty.json"
  run "$TOOL" --fail-on-outdated
  [ "$status" -eq 0 ]
}

@test "--output writes the same report to a file" {
  run "$TOOL" --output "$BATS_TEST_TMPDIR/report.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  expected="$("$TOOL")"
  [ "$(cat "$BATS_TEST_TMPDIR/report.md")" = "$expected" ]
}

@test "invalid input is a data error" {
  printf '[1, 2, 3]\n' >"$BATS_TEST_TMPDIR/bad.json"
  run "$TOOL" --input "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -eq 65 ]
}

@test "a failing brew is reported as unavailable" {
  export BREW_FAIL=1
  run "$TOOL"
  [ "$status" -eq 69 ]
}

@test "the report is stable for the same input" {
  a="$("$TOOL")"
  b="$("$TOOL")"
  [ "$a" = "$b" ]
}
