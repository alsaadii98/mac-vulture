cask "mac-vulture" do
  version "0.2.0"
  sha256 :no_check # replaced by release CI

  url "https://github.com/alsaadii98/mac-vulture/releases/download/v#{version}/MacVulture-v#{version}.dmg"
  name "Mac Vulture"
  desc "Fast, native, open-source Mac cleaner"
  homepage "https://github.com/alsaadii98/mac-vulture"

  depends_on macos: ">= :ventura"

  app "Mac Vulture.app"

  zap trash: [
    "~/Library/Application Support/Mac Vulture",
    "~/Library/Caches/app.macvulture.MacVulture",
    "~/Library/Logs/mac-vulture",
    "~/Library/Preferences/app.macvulture.MacVulture.plist",
    "~/.config/mac-vulture",
  ]
end
