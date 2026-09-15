#!/bin/bash
# App Store 판(샌드박스) 스모크 테스트. `make build-appstore` 뒤에 실행한다.
# 컨테이너 안 폴더는 읽히고(트리 정상), 컨테이너 밖 파일을 Finder(open -a)로 열면 파일은 열리되 폴더 목록은 권한이 없어
# 사이드바에 "폴더 접근 허용" 안내가 뜬다(덤프의 워크스페이스 이름 뒤 !). 열기 패널(powerbox)은 사람이 눌러야 하므로 여기서는 검사하지 않는다.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build-appstore/Build/Products/Debug/cmarks.app"
CONTAINER="$HOME/Library/Containers/com.changhyunyoo.cmarks/Data"
FAIL=0
pass() { echo "  ✔ $1"; }
fail() { echo "  ✘ $1"; FAIL=$((FAIL+1)); }
expect_contains() { if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 — 기대: '$2' / 실제: ${1:-<없음>}"; fi; }
appPid() { pgrep -x cmarks | while read -r pid; do ps -o args= -p "$pid" | grep -q "$APP" && echo "$pid"; done | head -1; }
kill_app() { local p; p=$(appPid); [ -n "$p" ] && kill "$p" 2>/dev/null; sleep 1; }
dumpline() { /usr/bin/log show --start "$1" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND category == "script"' --style compact 2>/dev/null | grep -F "[$2]" | grep -F "slots=" | tail -1 | sed 's/.*\] \[/[/' | tr -d '*'; }
wait_script() { for _ in $(seq 1 90); do sleep 1; /usr/bin/log show --start "$START" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND category == "script"' --style compact 2>/dev/null | grep -qE "script done|> quit" && return 0; done; echo "  (script done 대기 시간 초과)"; }

[ -d "$APP" ] || { echo "먼저 make build-appstore"; exit 1; }
echo "=== 샌드박스 확인 ==="
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null | grep -q '"com.apple.security.app-sandbox":true' && pass "app-sandbox 엔타이틀먼트" || fail "app-sandbox 엔타이틀먼트 없음"
[ -e "$APP/Contents/Frameworks/Sparkle.framework" ] && fail "Sparkle이 들어 있다" || pass "Sparkle 없음"
/usr/libexec/PlistBuddy -c "Print SUFeedURL" "$APP/Contents/Info.plist" >/dev/null 2>&1 && fail "SUFeedURL이 있다" || pass "SUFeedURL 없음"

# 컨테이너가 없으면 한 번 띄워 만든다
if [ ! -d "$CONTAINER" ]; then open -na "$APP" --args -CmarksDisableUpdater YES; sleep 4; kill_app; fi
[ -d "$CONTAINER" ] || { fail "컨테이너가 만들어지지 않음"; exit 1; }

echo "=== S1: 컨테이너 안 워크스페이스는 읽히고, 컨테이너 밖 파일은 열리되 폴더는 권한 없음 ==="
T=$(mktemp -d "$CONTAINER/tmp/cmarks-e2e.XXXX")
python3 - "$T" WS <<'PY'
import json, sys, time, uuid, urllib.parse, os
T = sys.argv[1]; names = sys.argv[2:]
os.makedirs(f"{T}/session", exist_ok=True); wss = []
for name in names:
    folder = f"{T}/{name}"; os.makedirs(folder, exist_ok=True)
    open(f"{folder}/README.md", "w").write(f"# {name}\n"); open(f"{folder}/second.md", "w").write(f"# {name} second\n")
    pane = str(uuid.uuid4()).upper(); tab = str(uuid.uuid4()).upper(); url = "file://" + urllib.parse.quote(f"{folder}/README.md")
    wss.append({"id": str(uuid.uuid4()).upper(), "name": name, "rootURL": "file://" + urllib.parse.quote(folder) + "/", "isEphemeral": False, "lastActiveAt": time.time()*1000,
        "layout": {"leaf": {"_0": {"raw": pane}}}, "panes": [{"id": {"raw": pane}, "activeTabID": tab, "tabs": [{"id": tab, "document": {"url": url}, "history": [{"url": url}], "historyIndex": 0, "isPinned": False, "isPreview": False, "scrollY": 0, "zoom": 1}]}],
        "focusedPaneID": {"raw": pane}, "focusHistory": [{"raw": pane}], "recentlyClosedTabs": [], "sidebar": {"expandedDirectories": [""]}})
json.dump({"schemaVersion": 1, "savedAt": time.time()*1000, "activeWorkspaceID": wss[0]["id"], "workspaces": wss, "windows": [{"workspaceID": w["id"]} for w in wss]}, open(f"{T}/session/session.json", "w"))
PY
OUT=$(mktemp -d /tmp/cmarks-sandbox-out.XXXX); printf '# outside\n![img](pic.png)\n' > "$OUT/note.md"
printf 'sleep 3000\ndump start\nsleep 8000\ndump afterOutside\nquit\n' > "$T/script.txt"
START=$(date '+%Y-%m-%d %H:%M:%S')
open -na "$APP" --args -CmarksSessionDirectory "$T/session" -CmarksDisableUpdater YES -CmarksScript "$T/script.txt"
sleep 6; open -a "$APP" "$OUT/note.md"
wait_script
L=$(dumpline "$START" start); echo "  $L"
expect_contains "$L" "→WS[README.md|active=README.md] win=vK" "컨테이너 안 워크스페이스가 열림(트리 정상: ! 없음)"
L=$(dumpline "$START" afterOutside); echo "  $L"
expect_contains "$L" "→$(basename "$OUT")![note.md|active=note.md]" "밖의 파일은 열리되 폴더는 읽을 수 없음(!)"
echo "--- 접근 로그 ---"; /usr/bin/log show --start "$START" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND (category == "access" OR category == "tree")' --style compact 2>/dev/null | grep -v Filtering | sed -E 's/^[^ ]+ ([^ ]+) [^ ]+ [^ ]+ /\1 /' | head -5
kill_app; rm -rf "$T" "$OUT"

echo; [ "$FAIL" = 0 ] && echo "ALL PASS" || echo "FAILURES: $FAIL"
