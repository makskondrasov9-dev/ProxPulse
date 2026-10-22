cask "proxpulse" do
  version "0.2.3"
  sha256 "a359b00e3a6c233ad53fad553ace8db6129d3d759426495b6e991a004556fd99"

  url "https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v#{version}/ProxPulse-v#{version}.dmg"
  name "ProxPulse"
  desc "Native Proxmox VE monitor and VM/LXC manager"
  homepage "https://github.com/makskondrasov9-dev/ProxPulse"

  auto_updates true
  depends_on macos: :sonoma
  app "ProxPulse.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/ProxPulse.app"]
  end

  caveats <<~EOS
    Launch ProxPulse from Applications once after installation.
    Then add its widgets from the macOS desktop widget gallery.
    For automatic widget registration and launch, use the installer:
      curl -fsSL https://raw.githubusercontent.com/makskondrasov9-dev/ProxPulse/main/scripts/install.sh | bash
  EOS
end
