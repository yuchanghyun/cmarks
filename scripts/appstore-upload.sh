#!/bin/bash
# App Store 판 archive → 배포 서명 → App Store Connect 업로드. 실행: make upload-appstore
#   필요: CMARKS_ASC_KEY_ID, CMARKS_ASC_ISSUER_ID, ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 (또는 CMARKS_ASC_KEY_PATH)
#   서명: 로컬 키체인의 "Apple Distribution"/"Mac Installer Distribution" 인증서를 쓰거나, 없으면 API 키의 클라우드 관리 인증서를 쓴다.
#   클라우드 서명은 키에 "클라우드 관리 배포 인증서 액세스" 권한이 있어야 한다("Cloud signing permission error"가 나면 권한 없음 →
#   Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + 로 Apple Distribution·Mac Installer Distribution을 로컬에 만들거나,
#   App Store Connect에서 그 권한을 켠 새 키를 만든다).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CMARKS_ASC_KEY_ID:?CMARKS_ASC_KEY_ID가 필요하다}"
: "${CMARKS_ASC_ISSUER_ID:?CMARKS_ASC_ISSUER_ID가 필요하다}"
KEY_PATH="${CMARKS_ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$CMARKS_ASC_KEY_ID.p8}"
[ -f "$KEY_PATH" ] || { echo "App Store Connect API 키 파일이 없다: $KEY_PATH" >&2; exit 1; }

TEAM_ID="${CMARKS_TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1 | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/' || true)
fi
[ -n "$TEAM_ID" ] || { echo "팀 ID를 알 수 없다(Developer ID 인증서 없음). CMARKS_TEAM_ID로 준다." >&2; exit 1; }

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1 | tr -d '"')
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml | head -1 | tr -d '"')
AS_OUT=build/release/appstore; rm -rf "$AS_OUT"; mkdir -p "$AS_OUT"
make gen >/dev/null

echo "App Store: cmarks-appstore $VERSION ($BUILD) archive…"
xcodebuild -project cmarks.xcodeproj -scheme cmarks-appstore -configuration Release -derivedDataPath build-appstore \
  -archivePath "$AS_OUT/cmarks-appstore.xcarchive" archive -quiet CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development"

cat > "$AS_OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

echo "App Store: 배포 서명 + 업로드…"
xcodebuild -exportArchive -archivePath "$AS_OUT/cmarks-appstore.xcarchive" -exportOptionsPlist "$AS_OUT/ExportOptions.plist" \
  -exportPath "$AS_OUT/export" -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$CMARKS_ASC_KEY_ID" -authenticationKeyIssuerID "$CMARKS_ASC_ISSUER_ID" -quiet
echo "App Store: 빌드 $VERSION ($BUILD) 업로드 완료. 처리(10~30분) 뒤 App Store Connect에서 버전 $VERSION을 만들고 이 빌드를 골라 심사에 제출한다."
