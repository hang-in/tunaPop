cask "tunapop" do
  version "0.1.0"
  sha256 "c0ebd09b268eeaefe57fc49d5bc855cb8ba440edf9c15316e7885f5216ae43a0"

  url "https://github.com/hang-in/tunapop/releases/download/v#{version}/tunaPop-#{version}.dmg"
  name "tunaPop"
  desc "PopClip-style macOS assistant powered by local LLMs"
  homepage "https://github.com/hang-in/tunapop"

  app "tunaPop.app"

  zap trash: [
    "~/Library/Application Support/tunaPop",
    "~/Library/Logs/tunaPop",
    "~/Library/Preferences/app.tunapop.plist"
  ]
end
