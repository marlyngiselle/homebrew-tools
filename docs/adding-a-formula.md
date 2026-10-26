# Adding a new formula in 3 steps

The example adds a tool called `dnscheck`. Replace the name, keep the shape.

## 1. Add the tool and its tests

```bash
mkdir -p tools/dnscheck/test/stubs
$EDITOR tools/dnscheck/dnscheck          # starts with VERSION="dev"
$EDITOR tools/dnscheck/dnscheck.1        # man page, `mandoc -T lint` clean
$EDITOR tools/dnscheck/test/dnscheck.bats
chmod +x tools/dnscheck/dnscheck
make lint test
```

The house rules, which every existing tool follows:

| Rule | Why |
| --- | --- |
| Bash 3.2 compatible | It runs under `/bin/bash` on a stock Mac, and CI tests it there |
| `VERSION="dev"` on its own line | The formula replaces it with the release version |
| `--help`, `--version`, `--json` where it makes sense | Predictable for people and for scripts |
| Documented exit codes, `64` for usage, `69` for a missing dependency | Usable from cron and CI |
| Read-only by default | Anything that changes state needs an explicit flag and a confirmation |
| Every external command stubbed in tests | The suite runs offline, on any OS, in seconds |

## 2. Add the formula

```bash
cp Formula/portcheck.rb Formula/dnscheck.rb
$EDITOR Formula/dnscheck.rb
```

Change the class name (`Dnscheck`), `desc` (under 80 characters, no leading article, not starting with the tool name), the dependencies and the three paths in `def install`. Keep `url` and `sha256` as they are. They already point to the current release, and the next release rewrites them.

Write a `test do` block that proves the tool works, not only that it starts. Each existing formula is an example. `portcheck` finds its own listening socket, `wifi-diag` parses its JSON, `brew-outdated-report` renders a fixture.

```bash
ruby -c Formula/dnscheck.rb
scripts/local-audit.sh
```

> [!NOTE]
> Until the next release, the published tarball does not contain `tools/dnscheck`, so `brew test-bot --only-formulae` on the pull request fails at the install step. That is expected. Merge, then release, and the release run builds and tests the new formula against a tarball that contains it.

## 3. Release

```bash
git switch main && git pull
git tag -a v0.2.0 -m "v0.2.0: add dnscheck"
git push origin v0.2.0
```

`release.yml` does the rest and opens a pull request with the new `url`, `sha256` and bottles for every formula. Review it and merge it. See [release-process.md](release-process.md).
