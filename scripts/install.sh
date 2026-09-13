#!/bin/bash
# /Applications에 설치하고 CLI를 PATH에 넣는다. 실행: make install
#
# 우선순위:
#   1) build/release/export/cmarks.app (make release가 만든 Developer ID 서명·공증본, 버전이 project.yml과 같을 때)
#   2) Release 빌드 후 재서명. 키체인에 Developer ID 인증서가 있으면 그것으로 깊게(--deep) 서명하고,
#      없으면 ad-hoc으로 서명하되 라이브러리 검증을 끈다. (앱 본체와 내장 Sparkle.framework의 팀 ID가 다르면
#      dyld가 "different Team IDs"로 실행을 거부한다. ad-hoc 본체 + ad-hoc 프레임워크도 hardened runtime에서는 같은 이유로 막힌다.)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1 | tr -d '"')
DEST=${CMARKS_INSTALL_DIR:-/Applications}   # 시험용 덮어쓰기. /Applications가 아니면 CLI·기본 앱 지정은 건너뛴다.
EXPORT=build/release/export/cmarks.app
SRC=""

if [ -d "$EXPORT" ] && [ "$(defaults read "$PWD/$EXPORT/Contents/Info.plist" CFBundleShortVersionString)" = "$VERSION" ]; then
  SRC="$EXPORT"; echo "공증 릴리스 빌드를 설치한다: $SRC ($VERSION)"
else
  make build CONFIG=Release
  SRC=build/Build/Products/Release/cmarks.app
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1 || true)
  if [ -n "$IDENTITY" ]; then
    echo "Developer ID로 재서명: $IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$SRC"
  else
    echo "Developer ID 인증서가 없어 ad-hoc으로 재서명한다(라이브러리 검증 해제)."
    ENT=$(mktemp /tmp/cmarks-entitlements.XXXXXX.plist)
    cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
PLIST
    codesign --force --deep --options runtime --entitlements "$ENT" --sign - "$SRC"
    rm -f "$ENT"
  fi
  codesign --verify --deep --strict "$SRC"
fi

if [ "$DEST" = /Applications ] && pgrep -x cmarks >/dev/null; then
  echo "실행 중인 cmarks를 종료한다."
  osascript -e 'tell application id "com.changhyunyoo.cmarks" to quit' >/dev/null 2>&1 || pkill -x cmarks || true
  sleep 1
fi
mkdir -p "$DEST"
rm -rf "$DEST/cmarks.app"
ditto "$SRC" "$DEST/cmarks.app"
echo "설치 완료: $DEST/cmarks.app ($(defaults read "$DEST/cmarks.app/Contents/Info.plist" CFBundleShortVersionString))"
[ "$DEST" = /Applications ] || exit 0

for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    install -m 755 scripts/cmarks "$dir/cmarks"
    echo "CLI 설치: $dir/cmarks"
    break
  fi
done
# .md 기본 앱으로 지정(CHECKPOINTS D-6). 앱이 자기 자신을 등록하고 종료한다.
"/Applications/cmarks.app/Contents/MacOS/cmarks" --set-default-handler || true
echo "cmarks를 .md 기본 앱으로 지정했다. 되돌리려면 Finder 정보 창에서 다른 앱을 고르면 된다."
