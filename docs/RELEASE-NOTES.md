# 릴리스 노트

## 1.3.5

- **탭 목록이 창 폭의 절반만 쓰고 그 안에서 스크롤되던 문제**를 고쳤습니다. 이제 탭 목록이 오른쪽 + 버튼 바로 왼쪽까지 이어집니다.

### English

- **Fixed the tab strip using only half of the window width and scrolling inside it.** The tab strip now extends all the way to the + button on the right.

## 1.3.4

- **Finder에서 연 파일은 마지막으로 쓴 창에서 열립니다.** 파일 ▸ 새 창(⌘⇧N)으로 연 빈 창이 앞에 있으면, 그 파일이 다른 창의 워크스페이스 폴더에 속해 있어도 다른 창으로 보내지 않고 그 빈 창을 그 폴더의 워크스페이스로 만들어 엽니다. 앞 창이 비어 있지 않을 때는 이전처럼 파일이 속한 워크스페이스가 있는 창에서 열고 그 창을 앞으로 가져옵니다.
- 창이 여러 개일 때 빈 창에서 Finder로 파일을 열면 워크스페이스 이름과 폴더가 정해지지 않고 파일만 열리던 문제를 고쳤습니다.

### English

- **Files opened from the Finder now open in the window you used last.** If an empty window opened with File ▸ New Window (⌘⇧N) is in front, the file opens there and that window becomes a workspace for the file's folder, even when another window already shows that folder. When the front window is not empty, the previous rule still applies: the file opens in the window showing its workspace, and that window comes forward.
- Fixed opening a file from the Finder into an empty window while other windows were open: the workspace ended up with no name or folder, showing only the file.

## 1.3.3

- **창을 모두 닫은 뒤 Finder에서 파일을 열어도 아무 일이 일어나지 않던 문제**를 고쳤습니다. 열기 요청을 창의 화면이 받아 처리하고 있어서, 창이 하나도 없으면 요청이 버려졌습니다(첫 번째는 닫힌 창의 잔상이 처리해 우연히 동작했습니다). 이제 앱이 요청을 직접 처리하고 필요하면 창을 다시 만듭니다.

### English

- **Fixed opening a file from the Finder doing nothing after all windows were closed.** Open requests were handled by the window's view, so with no window left they were dropped (the first attempt happened to work because the closed window's view was still around). The app now handles requests itself and re-creates a window when needed.

## 1.3.2

- **여러 창 관련 버그를 고쳤습니다.**
  - Finder에서 현재 창에 없는 워크스페이스의 파일을 열면 창이 하나 더 생기고, 그 뒤로 내용이 두 창에 뒤섞이거나 아무 창에도 뜨지 않던 문제. 파일 열기 이벤트마다 시스템이 기본 창을 추가로 만들던 것을 막았습니다.
  - 사이드바에서 파일이나 워크스페이스를 고르면 다른 창에 열리거나 모든 창이 바뀌던 문제. 사이드바·탭 바·빠른 열기·검색은 이제 그 동작을 한 창, 즉 그 조작을 한 창에만 적용합니다.
  - 창을 닫은 뒤 그 창에 있던 워크스페이스를 고르면 닫힌 창이 다시 나타나던 문제. 닫힌 창은 완전히 정리됩니다.
  - 마지막 창을 닫은 뒤 Finder에서 파일을 열면 아무 창도 뜨지 않던 문제.
  - 강제 종료나 크래시 뒤에 다시 실행하면 창이 하나도 나타나지 않을 수 있던 문제.
  - Finder에서 연 파일(임시 워크스페이스)만 앞 창에 둔 채 종료하면 다음 실행 때 창이 하나 더 생기던 문제.
- 창의 위치와 크기를 세션에 함께 저장해 다음 실행 때 그대로 복원합니다.

### English

- **Fixed several multi-window bugs.**
  - Opening a file from the Finder that belonged to a workspace not shown in the current window created an extra window, after which content could end up in the wrong window or in no window at all. The system was creating an additional default window for every open-file event; that no longer happens.
  - Choosing a file or workspace in the sidebar could open it in another window, or change every window. The sidebar, tab bar, Quick Open and Search now act only on the window they were used in.
  - After closing a window, choosing the workspace it had shown could bring the closed window back. Closed windows are now fully cleaned up.
  - Opening a file from the Finder after closing the last window showed no window at all.
  - After a force quit or a crash, the next launch could come up without any window.
  - Quitting while the front window showed only a temporary workspace (a file opened from the Finder) opened an extra window on the next launch.
- Window position and size are saved with the session and restored on the next launch.

## 1.3.1

- **Finder에서 마크다운 파일을 더블클릭해 앱을 실행하면 바로 종료되던 문제**를 고쳤습니다. 창이 만들어지는 레이아웃 도중에 창 상태를 기록하다가 시스템 예외가 났습니다.
- 새 창 단축키를 ⌘⇧N으로 바꿨습니다(설정 ▸ 단축키에서 변경 가능).

### English

- **Fixed a crash on launch when opening a Markdown file from the Finder.** Window state was recorded during the layout pass that creates the window, which raised a system exception.
- New Window is now ⌘⇧N (changeable in Settings ▸ Shortcuts).

## 1.3.0

- **여러 창.** 파일 ▸ 새 창(⌥⌘N)으로 창을 더 열고, 사이드바의 워크스페이스를 오른쪽 클릭해 "새 창에서 열기"를 고르면 그 워크스페이스가 새 창에 뜹니다. 워크스페이스 목록은 모든 창이 공유하고, 한 워크스페이스는 한 창에만 보입니다. 다른 창에 있는 워크스페이스를 고르면 그 창이 앞으로 옵니다. 열려 있던 창은 다음 실행 때 복원됩니다. 창 사이 탭 드래그는 아직 지원하지 않습니다.

### English

- **Multiple windows.** File ▸ New Window (⌥⌘N) opens another window, and right-clicking a workspace in the sidebar offers "Open in New Window". All windows share the workspace list; a workspace is shown in one window at a time, and choosing one that is open elsewhere brings that window forward. Open windows are restored on the next launch. Dragging tabs between windows is not supported yet.

## 1.2.1

- **Finder 선택 따라가기가 권한을 묻지 않고 바로 거부되던 문제**를 고쳤습니다. 앱에 Apple Events 자동화 엔타이틀먼트가 빠져 있어 macOS가 프롬프트 없이 막고 있었습니다. 1.2.0에서 한 번이라도 켜 봤다면 터미널에서 `tccutil reset AppleEvents com.changhyunyoo.cmarks`를 실행해 남은 거부 기록을 지운 뒤 다시 켜세요.

### English

- **Follow Finder Selection was denied without asking for permission.** The app lacked the Apple Events automation entitlement, so macOS blocked it silently. If you tried it in 1.2.0, run `tccutil reset AppleEvents com.changhyunyoo.cmarks` once in Terminal to clear the stale denial, then turn it on again.

## 1.2.0

- **Finder Quick Look 미리보기.** cmarks를 설치하면 Finder에서 마크다운 파일을 선택하고 스페이스바를 눌렀을 때 cmarks와 같은 GitHub 스타일로 보입니다. 코드 하이라이팅, 수식(KaTeX), 알림, 태스크 리스트, 이모지, 문서 옆 이미지까지 표시합니다. Mermaid 다이어그램은 Quick Look의 제약으로 코드로 보이며 앱에서 열면 그려집니다. QLMarkdown 같은 다른 마크다운 Quick Look 확장이 있으면 시스템 설정 ▸ 일반 ▸ 로그인 항목 및 확장 프로그램 ▸ Quick Look에서 하나만 켜 두세요.
- **워크스페이스에서 찾기(⌘⇧F).** 워크스페이스의 모든 마크다운 파일 내용을 찾아 파일·줄·문맥을 보여 주고, 고르면 그 파일을 열어 찾기 바를 그 위치로 맞춥니다.
- **Finder 선택 따라가기(보기 메뉴).** 켜 두면 Finder에서 마크다운 파일을 고를 때마다 cmarks가 미리보기 탭으로 보여 줍니다. 사라지지 않는 Quick Look처럼 씁니다. 처음 켤 때 자동화(Finder) 권한을 묻습니다.
- **사용자 CSS(설정 ▸ 외형).** 글꼴, 크기, 색 등 원하는 스타일을 모든 문서에 덧입힙니다.
- **읽던 자리 기억.** 파일별 마지막 스크롤 위치를 기억해 탭을 닫았다 열거나 앱을 다시 켜도 그 자리로 돌아갑니다.
- **파일 ▸ 최근 파일 열기** 메뉴.

### English

- **Quick Look preview in the Finder.** With cmarks installed, pressing Space on a Markdown file shows the same GitHub-style rendering as the app: syntax highlighting, math (KaTeX), alerts, task lists, emoji and images next to the document. Mermaid diagrams appear as code in Quick Look and render when you open the file in cmarks. If another Markdown Quick Look extension (such as QLMarkdown) is installed, keep only one enabled under System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look.
- **Find in Workspace (⌘⇧F).** Searches the text of every Markdown file in the workspace, lists file, line and context, and opens the match with the find bar positioned on it.
- **Follow Finder Selection (View menu).** While on, selecting a Markdown file in the Finder shows it in cmarks as a preview tab, like a Quick Look that never disappears. macOS asks for Automation (Finder) permission the first time.
- **Custom CSS (Settings ▸ Appearance).** Add your own font, size or color rules on top of the GitHub styles.
- **Remembers where you were.** The last scroll position of each file is restored when you reopen it, even after relaunching.
- **File ▸ Open Recent** menu.

## 1.1.1

- **도움말 ▸ 문제 신고…** 버전·macOS·설정·이번 실행의 최근 로그를 클립보드에 복사하고, 버전과 설치 방법이 채워진 GitHub 이슈 양식을 엽니다. 문서 내용은 포함되지 않습니다.
- 도움말 메뉴에 "GitHub에서 cmarks 보기"를 추가했습니다.
- `make install`이 공증본을 우선 설치하고, 로컬 빌드는 재서명합니다(로컬 Release 빌드가 실행 즉시 종료되던 문제).

### English

- **Help ▸ Report a Problem…** copies diagnostics (version, macOS, settings, recent log from this session) to the clipboard and opens a GitHub issue form with the version and install method filled in. No document content is included.
- Help ▸ cmarks on GitHub.
- `make install` now installs the notarized build when available and re-signs local builds (local Release builds used to quit immediately at launch).

## 1.1.0

- **자동 업데이트.** 새 버전이 나오면 앱이 알려 주고 바로 설치할 수 있습니다(Sparkle). 설정 ▸ 동작 ▸ 업데이트에서 끌 수 있고, cmarks 메뉴의 "업데이트 확인…"으로 직접 확인할 수 있습니다. Homebrew 설치는 `brew upgrade --cask cmarks`도 그대로 됩니다.
- **새 아이콘.** cmux와 같은 계열의 파란 그라데이션.
- README가 영어 기준으로 바뀌었습니다. 한국어는 README.ko.md에 있습니다.

### English

- **Automatic updates.** cmarks checks for new versions once a day and installs them in place (Sparkle). Turn it off in Settings ▸ Behavior ▸ Updates, or check manually with cmarks ▸ Check for Updates…. Homebrew installs can keep using `brew upgrade --cask cmarks`.
- **New app icon** in the same blue family as cmux.
- The main README is now English; the Korean one lives in README.ko.md.

## 1.0.1

- **영어 UI 지원.** macOS 시스템 언어가 영어이면 메뉴, 설정, 사이드바, 안내 문구가 영어로 나옵니다. 용어는 macOS 관례를 따릅니다(Show in Finder, Quick Open, Export as PDF, Actual Size 등). 한국어 시스템에서 영어로 쓰려면 시스템 설정 ▸ 일반 ▸ 언어 및 지역 ▸ 응용 프로그램에서 cmarks의 언어를 English로 지정합니다.
- "기본 편집기로 열기"를 "외부 편집기로 열기"로 바꾸고, .md 기본 앱이 cmarks 자신일 때 다른 편집기(없으면 TextEdit)를 고르도록 고쳤습니다.
- 대용량 문서 안내 배너도 앱 언어를 따릅니다.

### English

- **English UI.** Menus, settings, the sidebar and all messages follow the macOS system language, using standard macOS terminology (Show in Finder, Quick Open, Export as PDF, Actual Size). To use English on a Korean system, add cmarks under System Settings ▸ General ▸ Language & Region ▸ Applications.
- "Open in External Editor" replaces "Open in Default Editor" and no longer picks cmarks itself when cmarks is the default app for `.md` files (falls back to TextEdit).
- Large-document banners follow the app language.

## 1.0.0 (2026-09-10)

macOS용 네이티브 Markdown 뷰어. Quick Look 미리보기가 선택을 바꾸면 사라지는 문제를 대신한다.

### 기능

- **GitHub와 같은 렌더링**: cmark-gfm + GitHub 스타일시트. 표, 태스크 리스트, 취소선, 각주, 알림(Note·Tip·Important·Warning·Caution), 코드 하이라이팅, 이모지 숏코드, 수식(KaTeX), Mermaid 다이어그램, 헤딩 앵커, 프런트매터. 라이트·다크 자동 전환.
- **워크스페이스·탭·분할**: 폴더 단위 워크스페이스, 패인마다 탭, 오른쪽·아래 분할, 드래그 크기 조정, 패인 확대, 세션 복원. cmux와 같은 단축키 배치.
- **사이드바**: 파일 트리(파일 시스템 변경 자동 반영), 아웃라인(현재 헤딩 강조), 빠른 열기(⌘P, fuzzy).
- **라이브 리로드**: 파일을 저장하면 스크롤을 유지한 채 바뀐 부분만 갱신. 삭제·이동 감지와 자동 복구.
- **문서 도구**: 찾기(⌘F), 뒤로·앞으로, 확대·축소, 인쇄, PDF 내보내기, 링크 ⌘클릭(새 탭)·⌥클릭(분할).
- **설정**: 렌더링 확장 토글, 본문 폭, 마크다운 확장자·무시 폴더, 동작, 모든 단축키 직접 지정.
- **대용량 문서**: 2MB 초과는 하이라이팅 생략, 5MB 초과는 앞부분만 표시 후 "전체 표시".
- Finder "다음으로 열기", 드래그&드롭, `cmarks` CLI, `cmarks://open?path=` 딥링크. 설치 시 .md 기본 앱 지정.

### 요구 사항

- macOS 15 Sequoia 이상.

### 알려진 한계

- 웹(http) 링크는 항상 기본 브라우저에서 열린다.
- 창은 하나만 지원한다.
- UI는 한국어만 제공한다.
- `$5와 $10`처럼 달러 기호 두 개가 한 문단에 있으면 수식으로 오인될 수 있다(설정에서 수식을 끌 수 있다).

### English

A native Markdown reader for macOS. Replaces the Quick Look preview that disappears as soon as the selection changes.

- **Renders like GitHub**: cmark-gfm and GitHub's stylesheet. Tables, task lists, strikethrough, footnotes, alerts (Note, Tip, Important, Warning, Caution), syntax highlighting, emoji shortcodes, math (KaTeX), Mermaid diagrams, heading anchors, front matter. Light and dark follow the system.
- **Workspaces, tabs and splits**: folder-based workspaces, tabs per pane, split right or down, drag to resize, pane zoom, session restore. Same shortcut layout as cmux.
- **Sidebar**: file tree that follows file system changes, outline with the current heading highlighted, Quick Open (⌘P, fuzzy).
- **Live reload**: saving a file updates only what changed and keeps your scroll position. Deleted or moved files are detected and picked up again.
- **Reading tools**: Find (⌘F), back and forward, zoom, print, export as PDF, ⌘-click a link for a new tab and ⌥-click for a split.
- **Settings**: rendering extensions, content width, Markdown extensions and ignored folders, behavior, every shortcut.
- **Large documents**: highlighting is skipped above 2 MB; above 5 MB only the beginning is shown until you choose Show All.
- Finder "Open With", drag and drop, the `cmarks` CLI, `cmarks://open?path=` links. The installer can make cmarks the default app for `.md`.
- Requires macOS 15 Sequoia or later. Web links always open in the default browser; single window; Korean UI only in this version.

