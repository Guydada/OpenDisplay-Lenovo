class OpendisplayLenovo < Formula
  desc "Control Lenovo Legion Y34wz-30 lighting and display settings on macOS"
  homepage "https://github.com/Guydada/OpenDisplay-Lenovo"
  url "https://github.com/Guydada/OpenDisplay-Lenovo/archive/2c1724d2701375dc9008df84c546f3a567e9deb2.tar.gz"
  version "1.0.0"
  sha256 "8b82451c64160514cf04f6c9fb0434e3dd45bdd34b9498c32775a9397ed20486"
  license "GPL-3.0-or-later"

  depends_on xcode: ["16.0", :build]
  depends_on "xcodegen" => :build
  depends_on arch: :arm64
  depends_on macos: :sonoma

  preserve_rpath

  def install
    # macOS cannot nest another sandbox for Xcode's SDK macros inside Homebrew's build sandbox.
    config = buildpath/"Homebrew.xcconfig"
    config.write "OTHER_SWIFT_FLAGS = $(inherited) -Xfrontend -disable-sandbox\n"
    ENV["XCODE_XCCONFIG_FILE"] = config
    ENV.remove_cc_etc
    system "scripts/build-lenovo-local.sh"
    libexec.install "dist/OpenDisplay.app" => "OpenDisplay Lenovo.app"
    bin.install_symlink libexec/"OpenDisplay Lenovo.app/Contents/Helpers/opendisplay" => "opendisplay-lenovo"
  end

  def caveats
    <<~EOS
      Quit any running copy of OpenDisplay, then open the menu-bar app with:
        open "#{opt_libexec}/OpenDisplay Lenovo.app"
    EOS
  end

  test do
    app = libexec/"OpenDisplay Lenovo.app"
    system "/usr/bin/codesign", "--verify", "--deep", "--strict", app
    plist = app/"Contents/Info.plist"
    installed = shell_output("/usr/bin/plutil -extract CFBundleShortVersionString raw '#{plist}'").strip
    assert_equal version.to_s, installed
    assert_match "lenovo", shell_output("#{bin}/opendisplay-lenovo help")
  end
end
