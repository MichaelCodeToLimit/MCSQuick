class Mcsquick < Formula
  desc "Interactive Minecraft Java server setup"
  homepage "https://github.com/MichaelCodeToLimit/MCSQuick"
  url "https://github.com/MichaelCodeToLimit/MCSQuick/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "828ae7f8ff070540a6fdc40467923f12f0741d3439266b79a28ffca00c492340"
  license "MIT"

  depends_on "bash"
  depends_on "jq"

  def install
    pkgshare.install "mc-setup.sh", "mc-customize.sh", "README.md"
    (bin/"mcsquick").write <<~SH
      #!/bin/sh
      case "${1:-}" in
        --help|-h) echo "Usage: mcsquick            set up a new Minecraft server"; echo "       mcsquick customize  change an existing server"; exit 0 ;;
        customize|customise) shift; exec "#{Formula["bash"].opt_bin}/bash" "#{pkgshare}/mc-customize.sh" "$@" ;;
        *) exec "#{Formula["bash"].opt_bin}/bash" "#{pkgshare}/mc-setup.sh" "$@" ;;
      esac
    SH
  end

  test do
    assert_match "Usage", shell_output("#{bin}/mcsquick --help")
  end
end
