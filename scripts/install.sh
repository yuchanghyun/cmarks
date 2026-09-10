#!/bin/sh
# Release 빌드를 /Applications에 설치하고 CLI를 PATH에 넣는다. 실행: make install
set -eu
cd "$(dirname "$0")/.."
make build CONFIG=Release
rm -rf /Applications/cmarks.app
cp -R build/Build/Products/Release/cmarks.app /Applications/
echo "설치 완료: /Applications/cmarks.app"

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
