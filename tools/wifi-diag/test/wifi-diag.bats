#!/usr/bin/env bats
# Tests for wifi-diag. Every system command is a stub that replays a
# synthetic fixture (documentation address ranges only), so the suite
# runs offline and on any OS.

setup() {
  TOOL="$BATS_TEST_DIRNAME/../wifi-diag"
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  : >"$STUB_DIR/calls.log"
  PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  healthy_wifi
}

out() { cat >"$STUB_DIR/$1.out"; }
rc() { printf '%s\n' "$2" >"$STUB_DIR/$1.rc"; }

ping_ok() {
  cat <<PING
--- $1 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = $2/$2/$2/0.100 ms
PING
}

healthy_wifi() {
  printf 'Darwin\n' | out uname
  out route <<'R'
   route to: default
destination: default
    gateway: 192.0.2.1
  interface: en0
R
  out networksetup.listallhardwareports <<'N'

Hardware Port: Ethernet Adapter (en4)
Device: en4
Ethernet Address: 02:00:00:00:00:04

Hardware Port: Wi-Fi
Device: en0
Ethernet Address: 02:00:00:00:00:00
N
  printf 'Current Wi-Fi Network: lab-net\n' | out networksetup.getairportnetwork
  printf '192.0.2.23\n' | out ipconfig.getifaddr
  out scutil <<'S'
DNS configuration

resolver #1
  nameserver[0] : 192.0.2.1
  nameserver[1] : 198.51.100.53
  nameserver[2] : 192.0.2.1

resolver #2
  domain   : local
  nameserver[0] : 198.51.100.99
S
  ping_ok 192.0.2.1 2.500 | out ping.192.0.2.1
  ping_ok 1.1.1.1 14.200 | out ping.1.1.1.1
  printf 'name: apple.com\nip_address: 198.51.100.10\n' | out dscacheutil
  printf '<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>\n' | out curl
}

@test "--version and --help work without touching the network" {
  run "$TOOL" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "wifi-diag "* ]]
  run "$TOOL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-network"* ]]
  [ ! -s "$STUB_DIR/calls.log" ]
}

@test "unknown flags and bad values are usage errors" {
  run "$TOOL" --bogus
  [ "$status" -eq 64 ]
  run "$TOOL" --count 0
  [ "$status" -eq 64 ]
  run "$TOOL" --interface 'en0;rm'
  [ "$status" -eq 64 ]
}

@test "refuses to run outside macOS" {
  printf 'Linux\n' | out uname
  run "$TOOL"
  [ "$status" -eq 69 ]
  [[ "$output" == *"only runs on macOS"* ]]
}

@test "a healthy Wi-Fi link reports every check ok and exits 0" {
  run "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Interface      en0 (Wi-Fi)"* ]]
  [[ "$output" == *"Wi-Fi network  lab-net"* ]]
  [[ "$output" == *"IPv4 address   192.0.2.23"* ]]
  [[ "$output" == *"DNS servers    192.0.2.1, 198.51.100.53"* ]]
  [[ "$output" == *"Overall: ok"* ]]
}

@test "DNS servers come from the first resolver only, deduplicated" {
  run "$TOOL" --json --no-network
  printf '%s' "$output" | jq -e '.dns.servers == ["192.0.2.1", "198.51.100.53"]'
}

@test "--json is valid and carries numbers as numbers" {
  run "$TOOL" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .tool == "wifi-diag"
    and .interface.name == "en0"
    and .interface.hardware_port == "Wi-Fi"
    and .interface.ssid == "lab-net"
    and (.checks | map(.name)) == ["default_route", "gateway_latency", "internet_latency", "dns_resolution", "captive_portal"]
    and (.checks[] | select(.name == "gateway_latency") | .avg_ms == 2.5 and .loss_pct == 0)
    and .overall == "ok"'
}

@test "--no-network skips every probe" {
  run "$TOOL" --no-network
  [ "$status" -eq 0 ]
  ! grep -q -E '^(ping|curl|dscacheutil) ' "$STUB_DIR/calls.log"
  [[ "$output" == *"captive_portal     skipped"* ]]
}

@test "a redacted SSID is reported as hidden, not as an error" {
  printf 'You are not associated with an AirPort network.\n' | out networksetup.getairportnetwork
  printf '  BSSID : <redacted>\n  SSID : <redacted>\n' | out ipconfig.getsummary
  run "$TOOL" --json --no-network
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.interface.ssid == null and .interface.ssid_status == "redacted"'
}

@test "the SSID falls back to ipconfig getsummary" {
  printf 'You are not associated with an AirPort network.\n' | out networksetup.getairportnetwork
  printf '  SSID : backup-net\n' | out ipconfig.getsummary
  run "$TOOL" --json --no-network
  printf '%s' "$output" | jq -e '.interface.ssid == "backup-net"'
}

@test "an Ethernet default route is not treated as Wi-Fi" {
  sed -i.bak 's/interface: en0/interface: en4/' "$STUB_DIR/route.out"
  run "$TOOL" --json --no-network
  printf '%s' "$output" | jq -e '.interface.hardware_port == "Ethernet Adapter (en4)" and .interface.ssid_status == "not_wifi"'
}

@test "slow gateway is a warning and exits 1" {
  ping_ok 192.0.2.1 85.000 | out ping.192.0.2.1
  run "$TOOL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gateway_latency    warn     avg 85.000 ms to 192.0.2.1, above 30 ms"* ]]
}

@test "packet loss is a warning even when latency is fine" {
  printf '3 packets transmitted, 2 packets received, 33.3%% packet loss\nround-trip min/avg/max/stddev = 10/11/12/1 ms\n' | out ping.1.1.1.1
  run "$TOOL" --json
  [ "$status" -eq 1 ]
  printf '%s' "$output" | jq -e '(.checks[] | select(.name == "internet_latency") | .status == "warn" and .loss_pct == 33.3) and .overall == "warn"'
}

@test "an unreachable internet host is a failure and exits 2" {
  printf '3 packets transmitted, 0 packets received, 100.0%% packet loss\n' | out ping.1.1.1.1
  rc ping 2
  run "$TOOL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"internet_latency   fail     1.1.1.1 did not answer"* ]]
}

@test "a captive portal page is detected" {
  printf '<html><title>Hotel Wi-Fi login</title></html>\n' | out curl
  run "$TOOL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"captive portal detected"* ]]
}

@test "a failed name lookup is a failure" {
  : | out dscacheutil
  run "$TOOL" --json
  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '.checks[] | select(.name == "dns_resolution") | .status == "fail"'
}

@test "no default route means offline: exit 2 and no probes sent" {
  printf 'route: writing to routing socket: not in table\n' | out route
  rc route 1
  run "$TOOL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no default route, the Mac is offline"* ]]
  ! grep -q '^ping ' "$STUB_DIR/calls.log"
}

@test "--target and --count reach ping" {
  ping_ok 198.51.100.7 20.000 | out ping.198.51.100.7
  run "$TOOL" --target 198.51.100.7 --count 5
  [ "$status" -eq 0 ]
  grep -q '^ping -c 5 -q -t 5 198.51.100.7$' "$STUB_DIR/calls.log"
}
