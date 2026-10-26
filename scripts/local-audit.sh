#!/usr/bin/env bash
# Run, on a laptop, the checks CI runs on every pull request.
#
#   scripts/local-audit.sh            all checks that the machine can run
#   scripts/local-audit.sh --no-brew  skip the Homebrew checks
#
# Steps: ruby -c on every formula, ShellCheck on tools and scripts, the bats
# suites, actionlint on the workflows, then `brew style` on the formulae and,
# when the tap is installed, `brew audit --strict --online`. A missing tool
# is reported as skipped, never as passed. Exit 1 if any step failed.
#
# Note: the first `brew style` run makes Homebrew download its own RuboCop
# gems into its vendor directory. Pass --no-brew to avoid that.

set -uo pipefail

TAP="marlyngiselle/tools"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

USE_BREW=1
case "${1:-}" in
  --no-brew) USE_BREW=0 ;;
  -h | --help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *)
    printf 'local-audit: unknown argument: %s\n' "$1" >&2
    exit 64
    ;;
esac

passed=() failed=() skipped=()

step() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  if "$@"; then
    passed+=("$name")
  else
    failed+=("$name")
  fi
}

skip() {
  printf '\n==> %s\nskipped: %s\n' "$1" "$2"
  skipped+=("$1 ($2)")
}

have() { command -v "$1" >/dev/null 2>&1; }

shell_files() {
  # Every executable shell script in tools/, the test stubs and scripts/.
  find tools scripts -type f \( -perm -u+x -o -name '*.sh' \) -print | sort
}

ruby_syntax() {
  local f rc=0
  for f in Formula/*.rb; do ruby -c "$f" >/dev/null || rc=1; done
  [ "$rc" -eq 0 ] && printf 'Syntax OK (%s formulae)\n' "$(find Formula -name '*.rb' | wc -l | tr -d ' ')"
  return "$rc"
}

run_shellcheck() {
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(shell_files)
  shellcheck --severity=style "${files[@]}" && printf 'ShellCheck clean (%s files)\n' "${#files[@]}"
}

run_bats() {
  bats tools/*/test tests
}

brew_style() {
  brew style Formula/*.rb
}

brew_audit() {
  brew audit --strict --online --tap "$TAP"
}

if have ruby; then step "ruby -c" ruby_syntax; else skip "ruby -c" "ruby not installed"; fi
if have shellcheck; then step "shellcheck" run_shellcheck; else skip "shellcheck" "shellcheck not installed"; fi
if have bats && have jq; then step "bats" run_bats; else skip "bats" "bats or jq not installed"; fi
if have actionlint; then step "actionlint" actionlint; else skip "actionlint" "actionlint not installed"; fi

if [ "$USE_BREW" -eq 0 ]; then
  skip "brew style" "--no-brew"
  skip "brew audit" "--no-brew"
elif ! have brew; then
  skip "brew style" "brew not installed"
  skip "brew audit" "brew not installed"
else
  step "brew style" brew_style
  if brew tap | grep -qx "$TAP"; then
    step "brew audit" brew_audit
  else
    skip "brew audit" "tap $TAP is not installed; CI audits it with brew test-bot --only-tap-syntax"
  fi
fi

printf '\n%s\n' "Summary"
for s in ${passed[@]+"${passed[@]}"}; do printf '  pass  %s\n' "$s"; done
for s in ${skipped[@]+"${skipped[@]}"}; do printf '  skip  %s\n' "$s"; done
for s in ${failed[@]+"${failed[@]}"}; do printf '  FAIL  %s\n' "$s"; done
[ "${#failed[@]}" -eq 0 ]
