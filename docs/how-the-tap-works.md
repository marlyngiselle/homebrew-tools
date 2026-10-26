# How the tap works

A Homebrew tap is a Git repository whose name starts with `homebrew-`. This one is `marlyngiselle/homebrew-tools`, so Homebrew knows it as `marlyngiselle/tools`.

```bash
brew tap marlyngiselle/tools          # clones the repository into Homebrew's Taps directory
brew install marlyngiselle/tools/portcheck
```

`brew install marlyngiselle/tools/<formula>` taps automatically, so the first command is optional.

## What lives where

| Path | Role |
| --- | --- |
| `Formula/*.rb` | One Ruby class per tool. Homebrew reads only this directory |
| `tools/<name>/` | The tool itself: the script, its man page and its bats suite |
| `scripts/` | Release helpers used by CI and by hand |
| `.github/workflows/` | `tests.yml` for pull requests, `release.yml` for tags |

The formulae and the code they install live in the same repository. A formula does not install from the working tree, though. It installs from a release tarball, pinned by `sha256`, exactly like a formula in Homebrew's own core repository.

## Anatomy of a formula

```ruby
class Portcheck < Formula
  desc "Show which process listens on a TCP port and stop it safely"
  homepage "https://github.com/marlyngiselle/homebrew-tools"
  url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.1.0/homebrew-tools-0.1.0.tar.gz"
  sha256 "..."                       # checksum of that exact tarball
  license "MIT"
  head "https://github.com/marlyngiselle/homebrew-tools.git", branch: "main"

  livecheck do                       # `brew livecheck` finds new releases
    url :stable
    strategy :github_latest
  end

  uses_from_macos "lsof"             # system lsof on macOS, Homebrew's on Linux

  def install                        # runs inside the unpacked tarball
    inreplace "tools/portcheck/portcheck", /^VERSION="dev"$/, "VERSION=\"#{version}\""
    bin.install "tools/portcheck/portcheck"
    man1.install "tools/portcheck/portcheck.1"
  end

  test do                            # `brew test portcheck`, and CI
    ...
  end
end
```

The version comes from the tarball name (`homebrew-tools-0.1.0.tar.gz`), so it is never written twice. The scripts in `tools/` say `VERSION="dev"` and the formula stamps the real version at install time, which is why `portcheck --version` prints `0.1.0` once installed and `dev` from a clone.

## One tarball, several formulae

All formulae point to the same tarball. It contains `tools/` and `LICENSE`, and deliberately not `Formula/`. A formula carries the tarball's checksum, so a tarball that contained the formulae would change its own checksum every time the checksum was written. [ADR 0002](adr/0002-reproducible-tarball-without-formulae.md) explains the choice and how the tarball stays byte for byte reproducible.

## Bottles

A bottle is a prebuilt, relocatable package. With bottles, `brew install` downloads and pours instead of running `def install`. Bottles for this tap are built by `release.yml` on two macOS runners and uploaded as assets of the GitHub release they belong to. Each formula then gets a `bottle do` block that lists one `sha256` per macOS version and a `root_url` pointing to that release.

For script tools, bottling saves little time. It is kept because it proves the formula installs and passes `brew test` on a clean runner before anyone else installs it, and because it is how Homebrew ships software.

## What CI checks

| Check | Where | What it catches |
| --- | --- | --- |
| ShellCheck | `tests.yml`, unit job | Shell bugs in tools, stubs and scripts |
| bats on `/bin/bash` 3.2 | `tests.yml`, unit job | Behaviour regressions, and Bash 4 features that would break on a stock Mac |
| `ruby -c`, actionlint | `tests.yml`, unit job | Broken formula syntax, broken workflows |
| Checksum check | `tests.yml`, unit job | A formula whose `sha256` no longer matches its tag |
| `brew test-bot --only-tap-syntax` | `tests.yml`, test-bot job | `brew style` and `brew audit` for the whole tap |
| `brew test-bot --only-formulae` | `tests.yml` on pull requests, `release.yml` on tags | Install, `brew test`, linkage and bottling on macOS 15 and macOS 26 |
