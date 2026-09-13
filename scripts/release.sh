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

if [ -n "${CMARKS_NOTARY_PROFILE:-}" ] && ! xcrun notarytool history --keychain-profile "$CMARKS_NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "공증 프로파일 '$CMARKS_NOTARY_PROFILE'을(를) 키체인에서 찾을 수 없다. 먼저 다음을 실행한다:" >&2
  echo "  xcrun notarytool store-credentials $CMARKS_NOTARY_PROFILE --apple-id <Apple ID> --team-id <TEAM> --password <앱 암호>" >&2
  exit 1
fi

BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml | head -1 | tr -d '"')
PUBKEY=$(sed -n 's/^ *SPARKLE_PUBLIC_ED_KEY: *//p' project.yml | head -1 | tr -d '"')
if [ -n "${CMARKS_NOTARY_PROFILE:-}" ] && [ -z "$PUBKEY" ] && [ -z "${CMARKS_SKIP_APPCAST:-}" ]; then
  echo "project.yml의 SPARKLE_PUBLIC_ED_KEY가 비어 있어 자동 업데이트 피드를 만들 수 없다." >&2
  echo "  1회: <DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys 를 실행해 공개 키를 project.yml에 넣는다." >&2
  echo "  피드 없이 배포하려면 CMARKS_SKIP_APPCAST=1 로 다시 실행한다." >&2
  exit 1
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

# Sparkle appcast: 공증된 zip을 EdDSA 개인 키(키체인)로 서명해 appcast.xml 맨 앞에 항목을 넣는다.
SPARKLE_BIN=$(ls -d build/SourcePackages/artifacts/sparkle/Sparkle/bin "$HOME"/Library/Developer/Xcode/DerivedData/cmarks-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1 || true)
if [ "$NOTARIZED" = 1 ] && [ -n "$PUBKEY" ] && [ -n "$SPARKLE_BIN" ] && [ -z "${CMARKS_SKIP_APPCAST:-}" ]; then
  echo "appcast 서명 중…"
  SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP")
  python3 scripts/appcast.py --appcast appcast.xml --version "$VERSION" --build "$BUILD" \
    --url "https://github.com/yuchanghyun/cmarks/releases/download/v$VERSION/cmarks-$VERSION.zip" \
    --signature "$SIGNATURE" --notes docs/RELEASE-NOTES.md \
    --release-page "https://github.com/yuchanghyun/cmarks/releases/tag/v$VERSION"
else
  echo "appcast 갱신 건너뜀 (공증=$NOTARIZED, 공개 키=${PUBKEY:+있음}${PUBKEY:-없음}, Sparkle 도구=${SPARKLE_BIN:-없음})"
fi
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
echo "산출물:"; ls -la "$OUT"/*.zip "$OUT"/*.dmg "$OUT/checksums.txt" Casks/cmarks.rb appcast.xml
if [ "$NOTARIZED" = 1 ]; then
  echo "Developer ID 서명 + 공증 + 스테이플 완료. GitHub Releases에 올린 뒤 Casks/cmarks.rb와 appcast.xml을 커밋·푸시한다."
elif [ -n "$IDENTITY" ]; then
  echo "Developer ID 서명은 됐지만 공증은 건너뛰었다. CMARKS_NOTARY_PROFILE 을 설정하고 다시 실행하면 공증한다."
else
  echo "ad-hoc 서명이다. 다른 Mac에서는 우클릭 ▸ 열기가 필요하다. Developer ID 인증서를 만들면 자동으로 사용한다."
fi
