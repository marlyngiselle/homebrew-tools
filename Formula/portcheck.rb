class Portcheck < Formula
  desc "Show which process listens on a TCP port and stop it safely"
  homepage "https://github.com/marlyngiselle/homebrew-tools"
  url "https://github.com/marlyngiselle/homebrew-tools/releases/download/v0.1.0/homebrew-tools-0.1.0.tar.gz"
  sha256 "0cbf08246368dace01b089ec812b163a97733e31a5180a61bb2c9ed534c1b3ea"
  license "MIT"
  head "https://github.com/marlyngiselle/homebrew-tools.git", branch: "main"

  livecheck do
    url :stable
    strategy :github_latest
  end

  uses_from_macos "lsof"

  def install
    inreplace "tools/portcheck/portcheck", /^VERSION="dev"$/, "VERSION=\"#{version}\""
    bin.install "tools/portcheck/portcheck"
    man1.install "tools/portcheck/portcheck.1"
  end

  test do
    assert_match "portcheck #{version}", shell_output("#{bin}/portcheck --version")

    # Listen on a free port from the test process itself, then ask
    # portcheck who owns it: the answer must be this very PID.
    port = free_port
    server = TCPServer.new("127.0.0.1", port)
    begin
      report = JSON.parse(shell_output("#{bin}/portcheck --json #{port}"))
      assert_equal port, report["port"]
      assert_equal Process.pid, report["listeners"].first["pid"]
    ensure
      server.close
    end

    assert_match "nothing listens on TCP port #{port}",
                 shell_output("#{bin}/portcheck #{port} 2>&1", 1)
    assert_match "PORT must be a number", shell_output("#{bin}/portcheck 70000 2>&1", 64)
  end
end
