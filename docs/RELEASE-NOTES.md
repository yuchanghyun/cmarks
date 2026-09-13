# 릴리스 노트

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

