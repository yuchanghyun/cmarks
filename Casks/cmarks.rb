# Homebrew cask. 설치: brew tap yuchanghyun/cmarks https://github.com/yuchanghyun/cmarks && brew trust yuchanghyun/cmarks && brew install --cask cmarks
# scripts/release.sh 가 버전과 sha256을 갱신한다.
cask "cmarks" do
  version "1.3.5"
  sha256 "654ae98658c47a08ff47445bd74519b4571b3c772762a5474b8205cb656f278c"

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
