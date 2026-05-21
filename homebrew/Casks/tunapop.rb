cask "tunapop" do
  version "0.2.2"
  sha256 "b0dc19b84d6f7c275c06de16b2abc193bc2eb41661acf26dbd2f533b6ff88d52"

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
