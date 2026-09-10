#!/bin/bash
# 직접 배포용 빌드. 실행: make release
#
#   1) Release 아카이브 (키체인에 "Developer ID Application" 인증서가 있으면 그것으로, 없으면 ad-hoc)
#   2) 앱 zip 공증 → 스테이플, DMG 생성 → 서명 → 공증 → 스테이플 (CMARKS_NOTARY_PROFILE 이 있을 때)
#   3) SHA-256 체크섬과 Homebrew cask 초안
#
# 공증 프로파일 만들기(1회):
#   xcrun notarytool store-credentials cmarks --apple-id <Apple ID> --team-id <TEAM> --password <앱 암호>
# 그 뒤: CMARKS_NOTARY_PROFILE=cmarks make release
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1 | tr -d '"')
OUT=build/release
ARCHIVE="$OUT/cmarks.xcarchive"
rm -rf "$OUT"; mkdir -p "$OUT"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1 || true)
TEAM_ID=""
if [ -n "$IDENTITY" ]; then
  TEAM_ID=$(printf '%s' "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
  echo "서명: $IDENTITY (팀 $TEAM_ID)"
else
  echo "Developer ID 인증서가 없어 ad-hoc 서명으로 빌드한다. (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application)"
fi

make gen >/dev/null
if [ -n "$IDENTITY" ]; then
  xcodebuild -project cmarks.xcodeproj -scheme cmarks -configuration Release -archivePath "$ARCHIVE" archive -quiet \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" "DEVELOPMENT_TEAM=$TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp
  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" -quiet
  APP="$OUT/export/cmarks.app"
else
  xcodebuild -project cmarks.xcodeproj -scheme cmarks -configuration Release -archivePath "$ARCHIVE" archive -quiet
  APP="$ARCHIVE/Products/Applications/cmarks.app"
fi

codesign --verify --deep --strict "$APP"
echo "빌드 완료: $APP ($(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString))"

NOTARIZED=0
notarize() { # <파일>
  xcrun notarytool submit "$1" --keychain-profile "$CMARKS_NOTARY_PROFILE" --wait
}

ZIP="$OUT/cmarks-$VERSION.zip"
if [ -n "$IDENTITY" ] && [ -n "${CMARKS_NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "앱 공증 중…"; notarize "$ZIP"
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
  NOTARIZED=1
else
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

# DMG: 앱 + Applications 링크
STAGE="$OUT/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/cmarks-$VERSION.dmg"
hdiutil create -volname "cmarks $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [ -n "$IDENTITY" ]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  if [ "$NOTARIZED" = 1 ]; then
    echo "DMG 공증 중…"; notarize "$DMG"
    xcrun stapler staple "$DMG"
  fi
fi

(cd "$OUT" && shasum -a 256 "cmarks-$VERSION.zip" "cmarks-$VERSION.dmg" > checksums.txt)
ZIP_SHA=$(grep 'zip' "$OUT/checksums.txt" | cut -d' ' -f1)
mkdir -p Casks
cat > Casks/cmarks.rb <<CASK
# Homebrew cask. 설치: brew tap yuchanghyun/cmarks https://github.com/yuchanghyun/cmarks && brew trust yuchanghyun/cmarks && brew install --cask cmarks
# scripts/release.sh 가 버전과 sha256을 갱신한다.
cask "cmarks" do
  version "$VERSION"
  sha256 "$ZIP_SHA"

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
CASK

echo
echo "산출물:"; ls -la "$OUT"/*.zip "$OUT"/*.dmg "$OUT/checksums.txt" Casks/cmarks.rb
if [ "$NOTARIZED" = 1 ]; then
  echo "Developer ID 서명 + 공증 + 스테이플 완료. GitHub Releases에 올리면 된다."
elif [ -n "$IDENTITY" ]; then
  echo "Developer ID 서명은 됐지만 공증은 건너뛰었다. CMARKS_NOTARY_PROFILE 을 설정하고 다시 실행하면 공증한다."
else
  echo "ad-hoc 서명이다. 다른 Mac에서는 우클릭 ▸ 열기가 필요하다. Developer ID 인증서를 만들면 자동으로 사용한다."
fi
