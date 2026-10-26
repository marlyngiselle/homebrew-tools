class BrewOutdatedReport < Formula
  desc "Markdown report of outdated Homebrew formulae and casks"
  homepage "https://github.com/marlyngiselle/homebrew-tools"
  url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.1.0/homebrew-tools-0.1.0.tar.gz"
  sha256 "0cbf08246368dace01b089ec812b163a97733e31a5180a61bb2c9ed534c1b3ea"
  license "MIT"
  head "https://github.com/marlyngiselle/homebrew-tools.git", branch: "main"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on "jq"

  def install
    inreplace "tools/brew-outdated-report/brew-outdated-report", /^VERSION="dev"$/, "VERSION=\"#{version}\""
    bin.install "tools/brew-outdated-report/brew-outdated-report"
    man1.install "tools/brew-outdated-report/brew-outdated-report.1"
  end

  test do
    (testpath/"outdated.json").write <<~JSON
      {
        "formulae": [
          {"name": "foo", "installed_versions": ["1.2.3"], "current_version": "2.0.0",
           "pinned": false, "pinned_version": null},
          {"name": "bar", "installed_versions": ["4.1.0"], "current_version": "4.1.0_1",
           "pinned": false, "pinned_version": null}
        ],
        "casks": []
      }
    JSON

    ENV["SOURCE_DATE_EPOCH"] = "1767225600"
    report = shell_output("#{bin}/brew-outdated-report --input #{testpath}/outdated.json")
    assert_match "Generated 2026-01-01T00:00:00Z by brew-outdated-report #{version}.", report
    assert_match "| `foo` | 1.2.3 | 2.0.0 | major | no |", report
    assert_match "| `bar` | 4.1.0 | 4.1.0_1 | rebuild | no |", report
    assert_match "brew upgrade foo bar", report

    shell_output("#{bin}/brew-outdated-report --input #{testpath}/outdated.json --fail-on-outdated", 1)
  end
end
