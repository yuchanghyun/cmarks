#!/bin/bash
# README용 스크린샷·GIF를 만든다. 실행: scripts/screenshots.sh [앱 경로]
#   → docs/images/light.png, dark.png, live-reload.gif
# 화면 기록 권한(시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 화면 및 시스템 오디오 녹음)이 이 스크립트를 실행하는
# 터미널 앱에 있어야 한다. 사용자 세션은 건드리지 않는다(-CmarksSessionDirectory로 임시 세션 사용).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-build/Build/Products/Debug/cmarks.app}
OUT=docs/images; mkdir -p "$OUT"
WORK=$(mktemp -d /tmp/cmarks-shots.XXXXXX)
DOCS="$WORK/cmarks docs"; SESSION="$WORK/session"; mkdir -p "$DOCS/Guide" "$DOCS/Notes" "$SESSION"
FRAME_W=1280; FRAME_H=800

# ---------- 데모 문서 ----------
cat > "$DOCS/README.md" <<'MD'
# cmarks

A GitHub-accurate Markdown reader for macOS. Documents stay open in **workspaces**, **tabs** and **splits**, and update in place when a file changes.

> [!TIP]
> Press ⌘P to open any file in the workspace by name. ⌘D splits the pane to the right.

## Why a reader?

Quick Look shows a Markdown file only while it is selected. Click another file and the preview is gone. cmarks keeps documents open, so a README, a design note and the plan your AI tool just wrote can sit side by side.

## Rendering

| Element | Support |
|---|---|
| Tables, task lists, strikethrough | GitHub Flavored Markdown |
| Alerts | Note, Tip, Important, Warning, Caution |
| Code | highlight.js with the GitHub themes |
| Math | KaTeX, inline $E = mc^2$ and display |
| Diagrams | Mermaid |

```swift
let pipeline = RenderPipeline(settings: .github)
let html = try await pipeline.render(markdown, for: url)
```

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```mermaid
flowchart LR
  Finder --> cmarks
  Editor -->|save| cmarks
  AI[AI coding tool] -->|writes .md| cmarks
```

## Today

- [x] Open a folder as a workspace
- [x] Split right, split down
- [ ] Read the launch plan[^1]

[^1]: It lives in Notes/Launch plan.md and updates live.
MD
cat > "$DOCS/Notes/Launch plan.md" <<'MD'
# Launch plan

Target: Tuesday, October 6.

## Before launch

- [x] App icon
- [x] English README
- [ ] Screenshots and a short GIF
- [ ] Auto-update (Sparkle)
- [ ] Clean-Mac install check

## Launch week

| Day | Channel |
|---|---|
| Tue | Show HN |
| Wed | Product Hunt |
| Wed–Thu | Reddit, Korean communities |

> [!NOTE]
> This file is being edited by another app while cmarks shows it. Changes appear in place.
MD
cat > "$DOCS/Guide/Shortcuts.md" <<'MD'
# Shortcuts

| Action | Keys |
|---|---|
| Quick Open | ⌘P |
| Split right · Split down | ⌘D · ⌘⇧D |
| Focus pane | ⌥⌘ arrows |
| Next · Previous tab | ⌘⇧] · ⌘⇧[ |
| Find | ⌘F |
| Outline | ⌘⇧O |

Every shortcut can be changed in Settings ▸ Shortcuts.
MD
cat > "$DOCS/Guide/Workspaces.md" <<'MD'
# Workspaces

A workspace is a folder. The sidebar lists its Markdown files, Quick Open searches them, and tabs remember where you were. ⌘1–⌘8 switch between workspaces.
MD

# ---------- 세션(왼쪽: README + Shortcuts 탭, 오른쪽: Launch plan) ----------
python3 - "$DOCS" "$SESSION/session.json" <<'PY'
import json, sys, time, uuid, urllib.parse
docs, out = sys.argv[1], sys.argv[2]
def furl(rel): return "file://" + urllib.parse.quote(f"{docs}/{rel}")
def tab(rel): return {"id": str(uuid.uuid4()).upper(), "document": {"url": furl(rel)}, "history": [{"url": furl(rel)}], "historyIndex": 0, "isPinned": False, "isPreview": False, "scrollY": 0, "zoom": 1}
p1, p2, ws = (str(uuid.uuid4()).upper() for _ in range(3))
left = [tab("README.md"), tab("Guide/Shortcuts.md")]; right = [tab("Notes/Launch plan.md")]
now = time.time() * 1000
session = {"schemaVersion": 1, "savedAt": now, "activeWorkspaceID": ws, "workspaces": [{
    "id": ws, "name": "cmarks docs", "rootURL": "file://" + urllib.parse.quote(docs) + "/", "isEphemeral": False, "lastActiveAt": now,
    "layout": {"split": {"_0": {"id": str(uuid.uuid4()).upper(), "axis": "horizontal",
        "children": [{"leaf": {"_0": {"raw": p1}}}, {"leaf": {"_0": {"raw": p2}}}], "fractions": [0.56, 0.44]}}},
    "panes": [{"id": {"raw": p1}, "activeTabID": left[0]["id"], "tabs": left}, {"id": {"raw": p2}, "activeTabID": right[0]["id"], "tabs": right}],
    "focusedPaneID": {"raw": p1}, "focusHistory": [{"raw": p1}, {"raw": p2}], "recentlyClosedTabs": [],
    "sidebar": {"expandedDirectories": ["", "Guide", "Notes"]}}]}
json.dump(session, open(out, "w"), ensure_ascii=False, indent=1)
PY

# ---------- 창 목록 도구(CGWindowList) ----------
cat > "$WORK/windows.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "cmarks" {
    let b = w["kCGWindowBounds"] as! [String: Any]
    print("id=\(w["kCGWindowNumber"]!) pid=\(w["kCGWindowOwnerPID"]!) layer=\(w["kCGWindowLayer"]!) x=\(b["X"]!) y=\(b["Y"]!) w=\(b["Width"]!) h=\(b["Height"]!)")
}
SWIFT
WINDOWS="$WORK/windows"
swiftc -O "$WORK/windows.swift" -o "$WINDOWS" 2>/dev/null
SCREEN=$(defaults read com.changhyunyoo.cmarks "NSWindow Frame main" 2>/dev/null | awk '{print $5, $6, $7, $8}')
SCREEN=${SCREEN:-"0 0 1920 1080"}
FRAME="120 120 $FRAME_W $FRAME_H $SCREEN"

quit() { kill "$OURPID" 2>/dev/null || true; sleep 1; }

# 처음 실행 전에 이미 떠 있는 cmarks(사용자 설치본)는 건드리지 않는다: 우리 프로세스만 pid로 다룬다.
EXISTING=$(pgrep -x cmarks | tr '\n' ' ' || true)
launch_ours() { # 기존 pid를 제외하고 새 창을 찾는다
  open -na "$APP" --args -CmarksSessionDirectory "$SESSION" -CmarksDisableUpdater YES -restoreSession 1 -appearance "$1" \
    -showRenderStats 0 -sidebarVisible 1 -outlineVisible 1 "-NSWindow Frame main" "$FRAME" \
    "-NSWindow Frame SwiftUI.ModifiedContent<cmarks.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<cmarks.OpenRequestQueue>>>-1-AppWindow-1" "$FRAME"
  WIN=""
  for _ in $(seq 1 40); do
    for pid in $(pgrep -x cmarks); do
      case " $EXISTING " in *" $pid "*) continue;; esac
      WIN=$("$WINDOWS" | grep "pid=$pid " | grep "layer=0" | head -1 || true)
      [ -n "$WIN" ] && break 2
    done
    sleep 0.5
  done
  [ -n "$WIN" ] || { echo "cmarks 창을 찾지 못했다"; exit 1; }
  WID=$(sed -n 's/.*id=\([0-9]*\).*/\1/p' <<<"$WIN"); OURPID=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' <<<"$WIN")
  X=$(sed -n 's/.*x=\([0-9.]*\).*/\1/p' <<<"$WIN"); Y=$(sed -n 's/.*y=\([0-9.]*\).*/\1/p' <<<"$WIN")
  W=$(sed -n 's/.*w=\([0-9.]*\).*/\1/p' <<<"$WIN"); H=$(sed -n 's/.*h=\([0-9.]*\).*/\1/p' <<<"$WIN")
  echo "창 id=$WID pid=$OURPID 프레임=$X,$Y,$W,$H"
  sleep 3
}

launch_ours light
screencapture -x -o -l "$WID" "$OUT/light.png"
quit
launch_ours dark
screencapture -x -o -l "$WID" "$OUT/dark.png"
quit

# 라이브 리로드 GIF: 오른쪽 문서를 1.5초마다 고친다
launch_ours light
PLAN="$DOCS/Notes/Launch plan.md"
screencapture -x -v -R "$X,$Y,$W,$H" -V 11 "$WORK/live.mov" &
REC=$!
sleep 2
for step in 1 2 3; do
  python3 - "$PLAN" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("- [ ]", "- [x]", 1); p.write_text(t)
PY
  sleep 1.6
done
printf -- '- [ ] Post the announcement\n' >> "$PLAN"; sleep 1.6
python3 - "$PLAN" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
p.write_text(t.replace("Target: Tuesday, October 6.", "Target: **Tuesday, October 6** — three days to go."))
PY
wait $REC || true
quit
ffmpeg -y -loglevel error -i "$WORK/live.mov" \
  -vf "fps=8,scale=1280:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  "$OUT/live-reload.gif"
ls -la "$OUT"
echo "임시 폴더: $WORK"
