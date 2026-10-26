class WifiDiag < Formula
  desc "One-screen macOS network diagnostics with JSON output"
  homepage "https://github.com/marlyngiselle/homebrew-tools"
  url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.1.0/homebrew-tools-0.1.0.tar.gz"
  sha256 "0cbf08246368dace01b089ec812b163a97733e31a5180a61bb2c9ed534c1b3ea"
  license "MIT"
  head "https://github.com/marlyngiselle/homebrew-tools.git", branch: "main"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on :macos

  def install
    inreplace "tools/wifi-diag/wifi-diag", /^VERSION="dev"$/, "VERSION=\"#{version}\""
    bin.install "tools/wifi-diag/wifi-diag"
    man1.install "tools/wifi-diag/wifi-diag.1"
  end

  test do
    assert_match "wifi-diag #{version}", shell_output("#{bin}/wifi-diag --version")

    # --no-network keeps the test offline. The exit code depends on whether
    # the machine has a default route, so the JSON is what gets asserted.
    report = JSON.parse(shell_output("#{bin}/wifi-diag --json --no-network || true"))
    assert_equal "wifi-diag", report["tool"]
    assert_equal version.to_s, report["version"]
    assert_includes %w[ok fail], report["overall"]
    probes = report["checks"].reject { |check| check["name"] == "default_route" }
    assert_equal %w[skipped], probes.map { |check| check["status"] }.uniq

    assert_match "unknown argument", shell_output("#{bin}/wifi-diag --bogus 2>&1", 64)
  end
end
