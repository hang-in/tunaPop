cask "tunapop" do
  version "0.1.0"
  sha256 "e4c38e03a468a189ef66915fc4553bf8ce8a35ba3d94f5aa83d5e15a20ef421b"

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
