#!/usr/bin/env bats
# Tests for portcheck. lsof is replaced by a stub that replays a fixture;
# the kill tests use a real, disposable sleep process.

setup() {
  TOOL="$BATS_TEST_DIRNAME/../portcheck"
  export STUB_LOG="$BATS_TEST_TMPDIR/lsof.log"
  export LSOF_FIXTURE="$BATS_TEST_TMPDIR/lsof.out"
  : >"$STUB_LOG"
  : >"$LSOF_FIXTURE"
  PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  ME="$(id -un)"
}

teardown() {
  if [ -n "${VICTIM:-}" ]; then kill -KILL "$VICTIM" 2>/dev/null || true; fi
}

fixture() { printf '%s\n' "$@" >"$LSOF_FIXTURE"; }

spawn_victim() {
  sleep 300 &
  VICTIM=$!
  # Drop it from the job table so killing it later stays quiet.
  disown "$VICTIM" 2>/dev/null || true
}

@test "--version prints the name and version" {
  run "$TOOL" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "portcheck "* ]]
}

@test "--help documents every exit code" {
  run "$TOOL" --help
  [ "$status" -eq 0 ]
  for code in 0 1 2 64 69 77; do
    [[ "$output" == *"  $code "* ]]
  done
}

@test "no port is a usage error" {
  run "$TOOL"
  [ "$status" -eq 64 ]
}

@test "a port outside 1-65535 is rejected before lsof runs" {
  run "$TOOL" 70000
  [ "$status" -eq 64 ]
  run "$TOOL" abc
  [ "$status" -eq 64 ]
  [ ! -s "$STUB_LOG" ]
}

@test "--force without --kill is a usage error" {
  run "$TOOL" --force 8080
  [ "$status" -eq 64 ]
}

@test "lsof is asked for TCP listeners on that port only" {
  run "$TOOL" 8080
  grep -q -- "-iTCP:8080 -sTCP:LISTEN" "$STUB_LOG"
}

@test "a free port exits 1 and says so" {
  run "$TOOL" 8080
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing listens on TCP port 8080"* ]]
}

@test "a listener is shown with pid, command, user and every address once" {
  fixture p4242 cnode L"$ME" f21 n'*:3000' f22 n'[::]:3000' f23 n'*:3000'
  run "$TOOL" 3000
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == PID*COMMAND*USER*ADDRESS ]]
  [[ "${lines[1]}" == 4242*node*"$ME"*'*:3000,[::]:3000' ]]
}

@test "several processes sharing a port are all listed" {
  fixture p100 cnginx Lroot f6 n'*:80' p101 cnginx Lwww f6 n'*:80'
  run "$TOOL" 80
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "--json emits valid JSON with typed fields" {
  fixture p4242 c'my "app"' L"$ME" f21 n'127.0.0.1:3000'
  run "$TOOL" --json 3000
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.port == 3000 and .listeners[0].pid == 4242 and .listeners[0].command == "my \"app\"" and .listeners[0].addresses == ["127.0.0.1:3000"]'
}

@test "--json on a free port still emits valid JSON and exits 1" {
  run "$TOOL" --json 3000
  [ "$status" -eq 1 ]
  printf '%s' "$output" | jq -e '.listeners == []'
}

@test "--kill without a terminal and without --yes refuses" {
  spawn_victim
  fixture p"$VICTIM" csleep L"$ME" f3 n'*:3000'
  run "$TOOL" --kill 3000 </dev/null
  [ "$status" -eq 77 ]
  kill -0 "$VICTIM"
}

@test "--kill --dry-run prints the signals and sends none" {
  spawn_victim
  fixture p"$VICTIM" csleep L"$ME" f3 n'*:3000'
  run "$TOOL" --kill --force --dry-run 3000
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN: kill -TERM $VICTIM"* ]]
  [[ "$output" == *"DRY-RUN: kill -KILL $VICTIM"* ]]
  kill -0 "$VICTIM"
}

@test "--kill --yes stops the process with SIGTERM" {
  spawn_victim
  fixture p"$VICTIM" csleep L"$ME" f3 n'*:3000'
  run "$TOOL" --kill --yes 3000
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped $VICTIM (sleep) with SIGTERM"* ]]
  run kill -0 "$VICTIM"
  [ "$status" -ne 0 ]
}

@test "PID 1 is never stopped" {
  fixture p1 claunchd Lroot f3 n'*:3000'
  run "$TOOL" --kill --yes 3000
  [ "$status" -eq 77 ]
  [[ "$output" == *"refusing to stop protected process 1"* ]]
}

@test "a process owned by another user is refused without sudo" {
  [ "$(id -u)" -ne 0 ] || skip "running as root"
  spawn_victim
  fixture p"$VICTIM" csleep Lsomeoneelse f3 n'*:3000'
  run "$TOOL" --kill --yes 3000
  [ "$status" -eq 77 ]
  [[ "$output" == *"belongs to someoneelse"* ]]
  kill -0 "$VICTIM"
}

@test "a missing lsof exits 69" {
  run env PATH="/nonexistent" /bin/bash "$TOOL" 3000
  [ "$status" -eq 69 ]
}
