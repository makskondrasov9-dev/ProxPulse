cask "proxpulse" do
  version "0.2.1"
  sha256 "c043e083a9689a34bcb7585f05169ca9be76999350ec260594b4f398bd696bd7"

  url "https://github.com/makskondrasov9-dev/ProxPulse/releases/download/v#{version}/ProxPulse-v#{version}.dmg"
  name "ProxPulse"
  desc "Native Proxmox VE monitor and VM/LXC manager"
  homepage "https://github.com/makskondrasov9-dev/ProxPulse"

  auto_updates true
  depends_on macos: ">= :sonoma"
  app "ProxPulse.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/ProxPulse.app"]
    system_command "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                   args: ["-f", "#{appdir}/ProxPulse.app"]
    system_command "/usr/bin/pluginkit",
                   args: ["-a", "#{appdir}/ProxPulse.app/Contents/PlugIns/ProxPulseWidget.appex"]
    system_command "/usr/bin/pluginkit", args: ["-e", "use", "-i", "dev.proxpulse.app.widget"]
    system_command "/usr/bin/open", args: ["#{appdir}/ProxPulse.app"]
  end
end
