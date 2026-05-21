cask "tunapop" do
  version "0.2.1"
  sha256 "05d76a6d964a73089cce22dbf42887f0461d32050c1bbec3e82ddfafb445f70b"

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
