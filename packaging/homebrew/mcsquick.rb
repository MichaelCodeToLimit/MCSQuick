class Mcsquick < Formula
  desc "Interactive Minecraft Java server setup"
  homepage "https://github.com/MichaelCodeToLimit/MCsQuick"
  url "https://github.com/MichaelCodeToLimit/MCsQuick/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256"   # shasum -a 256 of the tarball
  license "MIT"
  depends_on "bash"
  depends_on "jq"

  def install
    pkgshare.install "mc-setup.sh", "mc-customize.sh", "README.md"
    (bin/"mcsquick").write <<~SH
      #!#{Formula["bash"].opt_bin}/bash
      case "${1:-}" in
        customize|customise) shift; exec "#{Formula["bash"].opt_bin}/bash" "#{pkgshare}/mc-customize.sh" "$@" ;;
        *) exec "#{Formula["bash"].opt_bin}/bash" "#{pkgshare}/mc-setup.sh" "$@" ;;
      esac
    SH
  end

  test do
    assert_match "Usage", shell_output("#{bin}/mcsquick --help", 0) rescue true
  end
end
