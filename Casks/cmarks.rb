# Homebrew cask. 설치: brew tap yuchanghyun/cmarks https://github.com/yuchanghyun/cmarks && brew trust yuchanghyun/cmarks && brew install --cask cmarks
# scripts/release.sh 가 버전과 sha256을 갱신한다.
cask "cmarks" do
  version "1.3.0"
  sha256 "1302d3e765ebc11d345f00bcce1a1bd5a23c8b04a7219dc55a829f07ffb3f6b9"

  url "https://github.com/yuchanghyun/cmarks/releases/download/v#{version}/cmarks-#{version}.zip"
  name "cmarks"
  desc "Native GitHub-style Markdown viewer with workspaces, tabs and splits"
  homepage "https://github.com/yuchanghyun/cmarks"

  depends_on macos: :sequoia

  app "cmarks.app"
  binary "#{appdir}/cmarks.app/Contents/Resources/cmarks", target: "cmarks"

  zap trash: [
    "~/Library/Application Support/cmarks",
    "~/Library/Preferences/com.changhyunyoo.cmarks.plist",
  ]
end
