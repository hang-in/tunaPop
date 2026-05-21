cask "tunapop" do
  version "0.2.4"
  sha256 "0964ce0df70f10d91d6a031fd56c4f25ac0eed086db6afae7a65d9f6ce42c04b"

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
