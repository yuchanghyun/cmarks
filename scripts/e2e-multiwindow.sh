#!/bin/bash
# 다중 창 E2E. 디버그 빌드(make build)를 실제로 띄워 -CmarksScript 시나리오로 조작하고 로그의 [label] 줄을 검사한다.
# 사용: make build && bash scripts/e2e-multiwindow.sh   ·  일부만: SCENARIOS="s5 s6" bash scripts/e2e-multiwindow.sh   (약 10분, 창이 뜨고 닫히므로 작업 중인 Mac에서는 방해가 될 수 있음)
# 화면이 잠겨 있어도 동작한다: 이때 AppKit 키 윈도우(*)는 생기지 않고 모델의 키(K)만 검사한다.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Build/Products/Debug/cmarks.app"
FAIL=0
pass() { echo "  ✔ $1"; }
fail() { echo "  ✘ $1"; FAIL=$((FAIL+1)); }
expect_contains() { # <dump line> <substring> <desc>
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 — 기대: '$2' / 실제: ${1:-<없음>}"; fi
}
expect_not_contains() { if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 — 있으면 안 됨: '$2' / 실제: $1"; fi; }
appPid() { pgrep -x cmarks | while read -r pid; do ps -o args= -p "$pid" | grep -q "$APP" && echo "$pid"; done | head -1; }
dumpline() { # <start> <label>
  /usr/bin/log show --start "$1" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND category == "script"' --style compact 2>/dev/null | grep -F "[$2]" | grep -F "slots=" | tail -1 | sed 's/.*\] \[/[/' | tr -d '*'
}
# K(모델 키)와 *(AppKit 키)가 어긋난 덤프가 있으면 알린다(화면이 잠겨 있으면 *가 없을 수 있음)
check_key_agreement() { local n; n=$(/usr/bin/log show --start "$1" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND category == "script"' --style compact 2>/dev/null | grep -F "slots=" | grep -E 'win=v\*' | wc -l | tr -d ' '); [ "$n" != 0 ] && fail "AppKit 키 창과 모델 키 창이 어긋난 덤프 $n개"; return 0; }
make_session() { # <dir> <ws names...> ; 각 ws 폴더에 README.md, 창은 모든 ws
  python3 - "$@" <<'PY'
import json, sys, time, uuid, urllib.parse, os
T = sys.argv[1]; names = sys.argv[2:]
os.makedirs(f"{T}/session", exist_ok=True)
wss = []
for name in names:
    folder = f"{T}/{name}"; os.makedirs(folder, exist_ok=True)
    open(f"{folder}/README.md", "w").write(f"# {name}\n")
    open(f"{folder}/second.md", "w").write(f"# {name} second\n")
    pane = str(uuid.uuid4()).upper(); tab = str(uuid.uuid4()).upper(); url = "file://" + urllib.parse.quote(f"{folder}/README.md")
    wss.append({"id": str(uuid.uuid4()).upper(), "name": name, "rootURL": "file://" + urllib.parse.quote(folder) + "/", "isEphemeral": False, "lastActiveAt": time.time()*1000,
        "layout": {"leaf": {"_0": {"raw": pane}}}, "panes": [{"id": {"raw": pane}, "activeTabID": tab, "tabs": [{"id": tab, "document": {"url": url}, "history": [{"url": url}], "historyIndex": 0, "isPinned": False, "isPreview": False, "scrollY": 0, "zoom": 1}]}],
        "focusedPaneID": {"raw": pane}, "focusHistory": [{"raw": pane}], "recentlyClosedTabs": [], "sidebar": {"expandedDirectories": [""]}})
json.dump({"schemaVersion": 1, "savedAt": time.time()*1000, "activeWorkspaceID": wss[0]["id"], "workspaces": wss,
           "windows": [{"workspaceID": w["id"]} for w in wss]}, open(f"{T}/session/session.json", "w"))
PY
}
start_app() { # <dir> <script text> ; 앱을 띄우고 START를 설정(비차단)
  local T=$1; printf '%s\n' "$2" > "$T/script.txt"
  START=$(date '+%Y-%m-%d %H:%M:%S')
  open -na "$APP" --args -CmarksSessionDirectory "$T/session" -CmarksDisableUpdater YES -CmarksScript "$T/script.txt"
}
wait_script() { for _ in $(seq 1 90); do sleep 1; /usr/bin/log show --start "$START" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND category == "script"' --style compact 2>/dev/null | grep -qE "script done|> quit" && return 0; done; echo "  (script done 대기 시간 초과)"; }
run_script() { start_app "$1" "$2"; wait_script; }
# 프로세스가 완전히 사라질 때까지 기다린다. 이전 인스턴스가 아직 종료 중이면 다음 시나리오의 파일 열기가 그쪽으로 가서(같은 경로) 검사가 흔들린다.
kill_app() { local p; p=$(appPid); [ -n "$p" ] && kill "$p" 2>/dev/null; for _ in $(seq 1 20); do [ -z "$(appPid)" ] && return 0; sleep 0.25; done; pkill -9 -f "$APP" 2>/dev/null; sleep 0.5; }

s1() {
echo "=== S1: Finder 열기 이벤트가 창을 복제하지 않는다 ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" WS
mkdir -p "$T/other"; printf '# other\n' > "$T/other/note.md"
start_app "$T" "sleep 2000
dump start
sleep 6000
dump afterOpen
sleep 4000
dump afterSecond"
sleep 4
open -a "$APP" "$T/other/note.md"        # 실제 LaunchServices 이벤트
sleep 5
open -a "$APP" "$T/WS/second.md"         # 숨겨진 WS 안의 파일
wait_script
L=$(dumpline "$START" afterOpen); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "창이 1개, 미매핑 창 없음"
expect_contains "$L" "→other[note.md|active=note.md]" "note.md가 임시 워크스페이스 other로 열림"
L=$(dumpline "$START" afterSecond); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "두 번째 열기 후에도 창 1개"
expect_contains "$L" "→WS[README.md,second.md|active=second.md]" "WS가 다시 표시되고 second.md 탭 추가"
check_key_agreement "$START"; kill_app; rm -rf "$T"
}

# S1 인스턴스는 quit 없이 SIGTERM으로 죽인다(강제 종료 뒤 AppKit이 hasPersistentStateToRestore=1로 보고 SwiftUI가 창을 만들지 않던 경로를 S2 시작에서 검사).

s2() {
echo "=== S2: 두 창, 창을 겨냥한 동작(강제 종료 뒤 재실행) ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" A B
mkdir -p "$T/outside"; printf '# out\n' > "$T/outside/out.md"
run_script "$T" "sleep 3000
dump start
key 1
sleep 500
open $T/B/second.md
sleep 800
dump openInB
key 0
sleep 500
open $T/A/second.md
sleep 800
dump openInA
activate B
sleep 800
dump activateBfromA
newWindow
sleep 1500
dump newWindow
closeWindow 2
sleep 1000
dump closedWindow
openOutside $T/B/README.md
sleep 1500
dump finderB
key 0
sleep 500
openOutside $T/outside/out.md
sleep 1500
dump finderOutside
quit"
L=$(dumpline "$START" start); echo "  $L"
expect_contains "$L" "windows=2 unmapped=0" "시작: 창 2개"
expect_contains "$L" "→A[README.md|active=README.md] win=v" "기본 창 A 표시(실행 직후 어느 창이 키인지는 AppKit이 정한다)"
L=$(dumpline "$START" openInB); echo "  $L"
expect_contains "$L" "→B[README.md,second.md|active=second.md]" "창 B에서 열면 B에만"
expect_contains "$L" "→A[README.md|active=README.md]" "A는 그대로"
expect_contains "$L" "active=B" "키 윈도우 전환 후 활성은 B"
L=$(dumpline "$START" openInA); echo "  $L"
expect_contains "$L" "→A[README.md,second.md|active=second.md]" "창 A에서 열면 A에만"
expect_contains "$L" "→B[README.md,second.md|active=second.md] win=v " "B는 그대로(키 아님)"
L=$(dumpline "$START" activateBfromA); echo "  $L"
expect_contains "$L" "→B[README.md,second.md|active=second.md] win=vK" "A에서 B를 고르면 B 창이 키로"
expect_contains "$L" "→A[README.md,second.md|active=second.md] win=v " "A 창은 그대로 A"
L=$(dumpline "$START" newWindow); echo "  $L"
expect_contains "$L" "windows=3 unmapped=0" "새 창 → 3개"
expect_contains "$L" "→<start>[|active=-]" "새 창은 빈 임시 워크스페이스"
L=$(dumpline "$START" closedWindow); echo "  $L"
expect_contains "$L" "windows=2 unmapped=0" "닫으면 2개"
expect_not_contains "$L" "<start>" "빈 임시 워크스페이스는 사라짐"
L=$(dumpline "$START" finderB); echo "  $L"
expect_contains "$L" "→B[README.md,second.md|active=README.md] win=vK" "Finder에서 B 파일 → B 창이 키, README 탭 활성"
expect_contains "$L" "windows=2" "창 수 유지"
L=$(dumpline "$START" finderOutside); echo "  $L"
expect_contains "$L" "→outside[out.md|active=out.md] win=vK" "밖의 파일 → 키 윈도우(A 창)에 임시 워크스페이스"
expect_contains "$L" "→B[README.md,second.md|active=README.md]" "B 창 그대로"
expect_contains "$L" "workspaces=A,outside,B" "A는 목록에 남고 outside 추가"
sleep 2
echo "--- 저장된 세션 ---"; python3 -c "
import json; d=json.load(open('$T/session/session.json')); print('  windows:', [(w['workspaceID'][:8], (w.get('frame') or '')[:20]) for w in d.get('windows') or []]); print('  workspaces:', [w['name'] for w in d['workspaces']])"
SAVED_WINDOWS=$(python3 -c "import json; print(len(json.load(open('$T/session/session.json')).get('windows') or []))")
[ "$SAVED_WINDOWS" = "1" ] && pass "임시(outside) 창은 저장 안 되고 B 창만 저장" || fail "저장된 창 수: $SAVED_WINDOWS (기대 1)"
}

s3() {
echo "=== S3: 재실행 시 창 복원(중복 없음) ==="
run_script "$T" "sleep 4000
dump relaunch
quit"
L=$(dumpline "$START" relaunch); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "저장된 창 1개만 복원(임시 워크스페이스 창은 없음)"
expect_contains "$L" "→B[" "복원된 창은 B"
sleep 2; rm -rf "$T"
}

s5() {
echo "=== S5: 마지막 창을 닫은 뒤 Finder 열기·Dock 재열기 ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" WS
start_app "$T" "sleep 2500
dump start
closeWindow 0
sleep 1500
dump closed
sleep 10000
dump afterFinderOpen
sleep 6000
dump afterReopen
quit"
sleep 7
open -a "$APP" "$T/WS/second.md"        # 창이 없는 상태에서 Finder 열기(open은 전달까지 수 초 걸릴 수 있음)
sleep 4
open -a "$APP"                           # Dock 클릭과 같은 재열기 이벤트
wait_script
L=$(dumpline "$START" closed); echo "  $L"
expect_contains "$L" "slots= |" "닫으면 슬롯이 남지 않음"
expect_contains "$L" "windows=0" "보이는 창 없음"
L=$(dumpline "$START" afterFinderOpen); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "Finder 열기로 창이 정확히 1개 생김"
expect_contains "$L" "→WS[README.md,second.md|active=second.md] win=vK" "그 창이 second.md를 보여 줌"
L=$(dumpline "$START" afterReopen); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "재열기 후에도 창 1개"
check_key_agreement "$START"; check_key_agreement "$START"; kill_app; rm -rf "$T"
}

s6() {
echo "=== S6: 둘째 창을 닫은 뒤 그 워크스페이스를 고르면 현재 창에서 열린다 ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" A B
run_script "$T" "sleep 3000
dump start
closeWindow 1
sleep 1500
dump closedB
activate B
sleep 1000
dump activateB
open $T/B/second.md
sleep 800
dump openInB
activate A
sleep 800
dump backToA
quit"
L=$(dumpline "$START" closedB); echo "  $L"
expect_contains "$L" "slots=C0DE0000→A[README.md|active=README.md] win=vK | windows=1 unmapped=0" "B 창을 닫으면 슬롯 1개, 창 1개"
expect_contains "$L" "workspaces=A,B" "B 워크스페이스는 목록에 남음(영구)"
L=$(dumpline "$START" activateB); echo "  $L"
expect_contains "$L" "slots=C0DE0000→B[README.md|active=README.md] win=vK | windows=1 unmapped=0" "B를 고르면 같은 창에서 B 표시, 숨은 창 부활 없음"
L=$(dumpline "$START" openInB); echo "  $L"
expect_contains "$L" "slots=C0DE0000→B[README.md,second.md|active=second.md] win=vK | windows=1" "B에서 파일 열기"
L=$(dumpline "$START" backToA); echo "  $L"
expect_contains "$L" "slots=C0DE0000→A[README.md|active=README.md] win=vK | windows=1" "다시 A"
check_key_agreement "$START"; check_key_agreement "$START"; kill_app; rm -rf "$T"
}

s4() {
echo "=== S4: 앱이 꺼진 상태에서 파일로 실행 ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" WS; mkdir -p "$T/other"; printf '# other\n' > "$T/other/note.md"
printf 'sleep 5000\ndump launchWithFile\nquit\n' > "$T/script.txt"
BEFORE=$(ls ~/Library/Logs/DiagnosticReports/ | grep -c "^cmarks-" || true)
START=$(date '+%Y-%m-%d %H:%M:%S')
# 파일을 실행 명령에 함께 넘긴다(Finder에서 더블클릭해 앱을 띄우는 것과 같다). 실행 직후 따로 보내면 LaunchServices가 -600으로 거부할 수 있다.
open -na "$APP" "$T/other/note.md" --args -CmarksSessionDirectory "$T/session" -CmarksDisableUpdater YES -CmarksScript "$T/script.txt"
for _ in $(seq 1 30); do sleep 1; /usr/bin/log show --start "$START" --predicate 'subsystem == "com.changhyunyoo.cmarks" AND category == "script"' --style compact 2>/dev/null | grep -q "script done" && break; done
AFTER=$(ls ~/Library/Logs/DiagnosticReports/ | grep -c "^cmarks-" || true)
[ "$AFTER" = "$BEFORE" ] && pass "크래시 없음" || fail "크래시 리포트 생성"
L=$(dumpline "$START" launchWithFile); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "창 1개"
expect_contains "$L" "note.md|active=note.md" "파일이 열림"
check_key_agreement "$START"; check_key_agreement "$START"; kill_app; rm -rf "$T"

exit $FAIL

}

s7() {
echo "=== S7: 창 두 개를 모두 닫은 뒤 Finder에서 열기, 다시 닫고 또 열기(사용자 보고 흐름) ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" A B
mkdir -p "$T/outside"; printf '# out\n' > "$T/outside/out.md"
start_app "$T" "sleep 3000
dump start
key 1
sleep 500
closeWindow 1
sleep 1500
dump closedB
closeWindow 0
sleep 1500
dump closedA
sleep 6000
dump afterFinderOpen
sleep 8000
dump afterOutside
closeWindow 0
sleep 1500
dump closedAgain
sleep 10000
dump afterThird
quit"
sleep 10
open -a "$APP" "$T/B/second.md"          # 창이 하나도 없는 상태에서 B 안의 파일(t≈10s, 덤프는 t≈14s)
sleep 7
open -a "$APP" "$T/outside/out.md"       # 이어서 어느 워크스페이스에도 없는 파일(t≈17s, 덤프는 t≈22s)
sleep 11
open -a "$APP" "$T/A/second.md"          # 다시 닫은 뒤 세 번째 열기(1.3.2에서 무시되던 경로, t≈28s, 덤프는 t≈33s)
wait_script
L=$(dumpline "$START" closedA); echo "  $L"
expect_contains "$L" "slots= | windows=0" "두 창을 모두 닫으면 슬롯·창 없음"
L=$(dumpline "$START" afterFinderOpen); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "Finder 열기로 창 1개"
expect_contains "$L" "→B[README.md,second.md|active=second.md] win=vK" "그 창이 B의 second.md를 보여 줌"
L=$(dumpline "$START" afterOutside); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "밖의 파일도 같은 창에"
expect_contains "$L" "→outside[out.md|active=out.md] win=vK" "임시 워크스페이스 outside 표시"
L=$(dumpline "$START" closedAgain); echo "  $L"
expect_contains "$L" "slots= | windows=0" "다시 닫으면 창 없음"
L=$(dumpline "$START" afterThird); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "세 번째 열기도 창 1개"
expect_contains "$L" "→A[README.md,second.md|active=second.md] win=vK" "A의 second.md 표시"
check_key_agreement "$START"; kill_app; rm -rf "$T"
}

s8() {
echo "=== S8: ⌘⇧N으로 연 빈 창이 키일 때 Finder 열기는 그 창으로 ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" WS
mkdir -p "$T/other"; printf '# other\n' > "$T/other/note.md"
start_app "$T" "sleep 3000
newWindow
sleep 1500
newWindow
sleep 1500
key 2
sleep 500
dump before
sleep 7000
dump afterInside
sleep 7000
dump afterOutside
quit"
sleep 10
open -a "$APP" "$T/WS/second.md"         # 첫 창 WS 폴더 안의 파일 → 키 창(빈 시작)에서
sleep 7
open -a "$APP" "$T/other/note.md"        # 밖의 파일 → 같은 키 창? (키 창은 이제 WS 폴더의 임시 워크스페이스라 비어 있지 않음 → 임시 워크스페이스 추가)
wait_script
L=$(dumpline "$START" before); echo "  $L"
expect_contains "$L" "windows=3 unmapped=0" "창 3개"
expect_contains "$L" "→<start>[|active=-] win=vK" "마지막 창(빈 시작)이 키"
L=$(dumpline "$START" afterInside); echo "  $L"
expect_contains "$L" "→WS[README.md|active=README.md] win=v " "첫 창 WS는 그대로(키 아님)"
expect_contains "$L" "→WS[second.md|active=second.md] win=vK" "키 창이 WS 폴더의 워크스페이스가 되어 second.md 표시"
expect_contains "$L" "windows=3 unmapped=0" "창 수 유지"
L=$(dumpline "$START" afterOutside); echo "  $L"
expect_contains "$L" "→other[note.md|active=note.md] win=vK" "밖의 파일은 키 창의 새 임시 워크스페이스에"
expect_contains "$L" "windows=3 unmapped=0" "창 수 유지"
check_key_agreement "$START"; kill_app; rm -rf "$T"
}

s9() {
echo "=== S9: 메뉴 탭 동작(다음·이전·번호·분할·닫기)이 앱을 종료시키지 않는다 ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" WS
start_app "$T" "sleep 3000
open $T/WS/second.md
sleep 800
nextTab
sleep 300
dump afterNext
prevTab
sleep 300
dump afterPrev
tab 1
sleep 300
dump afterTab1
splitRight
sleep 800
closePane
sleep 800
dump afterClosePane
quit"
wait_script
L=$(dumpline "$START" afterNext); echo "  $L"
expect_contains "$L" "→WS[README.md,second.md|active=README.md]" "다음 탭(끝에서 처음으로)"
L=$(dumpline "$START" afterPrev); echo "  $L"
expect_contains "$L" "→WS[README.md,second.md|active=second.md]" "이전 탭"
L=$(dumpline "$START" afterTab1); echo "  $L"
expect_contains "$L" "→WS[README.md,second.md|active=README.md]" "탭 1"
L=$(dumpline "$START" afterClosePane); echo "  $L"
expect_contains "$L" "→WS[" "분할 후 패인 닫기 뒤에도 살아 있음"
check_key_agreement "$START"; kill_app; rm -rf "$T"
}

s10() {
echo "=== S10: 마지막 창을 닫은 뒤 메뉴 '새 창'이 창을 되살린다(App Store 심사 2.1(a)·4) ==="
T=$(mktemp -d /tmp/cmarks-e2e.XXXX); make_session "$T" WS
run_script "$T" "sleep 3000
closeWindow 0
sleep 1500
dump closed
newWindow
sleep 2500
dump afterNewWindow
quit"
L=$(dumpline "$START" closed); echo "  $L"
expect_contains "$L" "slots= | windows=0" "창 없음"
L=$(dumpline "$START" afterNewWindow); echo "  $L"
expect_contains "$L" "windows=1 unmapped=0" "새 창으로 창 1개"
expect_contains "$L" "→WS[README.md|active=README.md] win=vK" "마지막 워크스페이스 WS가 되살아남"
expect_not_contains "$L" "<start>" "빈 시작 워크스페이스가 생기지 않음"
check_key_agreement "$START"; kill_app; rm -rf "$T"
}

for s in ${SCENARIOS:-s1 s2 s3 s5 s6 s7 s8 s9 s10 s4}; do "$s"; done
echo; [ "$FAIL" = 0 ] && echo "ALL PASS" || echo "FAILURES: $FAIL"
