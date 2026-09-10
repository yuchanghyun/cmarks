# cmarks

macOS 전용 네이티브 Markdown 뷰어(읽기 전용). GitHub 스타일 렌더링, cmux식 워크스페이스·탭·스플릿 레이아웃.
Quick Look 미리보기가 선택을 바꾸면 사라지는 문제를 대신한다. 전체 설계와 단계별 계획은 [docs/PLAN.md](docs/PLAN.md).

## 설치

- **DMG**: [Releases](https://github.com/yuchanghyun/cmarks/releases)에서 `cmarks-<버전>.dmg`를 받아 Applications 폴더로 끌어 넣는다. Developer ID 서명·공증된 빌드다.
- **Homebrew**: `brew tap yuchanghyun/cmarks https://github.com/yuchanghyun/cmarks && brew trust yuchanghyun/cmarks && brew install --cask cmarks` (서드파티 tap이라 `brew trust`가 한 번 필요하다)
- **소스에서**: 아래 "빌드와 실행".

라이선스는 [MIT](LICENSE). 무료다.

## 요구 사항

- macOS 15 이상(실행), Xcode 26.x(빌드)
- 배포 절차는 [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md), 변경 내역은 [docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md)
- `brew install xcodegen node pnpm`

## 빌드와 실행

```sh
make assets   # web/ 의존성 설치 후 App/Resources/web/vendor 채우기(최초 1회, 갱신 시)
make icon     # 임시 앱 아이콘 생성(최초 1회)
make run      # project.yml → xcodeproj 생성, 빌드, 실행
make test     # SwiftPM 패키지 테스트 + 앱 타겟 테스트
make install  # Release 빌드를 /Applications에 설치
```

`cmarks.xcodeproj`, `App/Info.plist`, `App/cmarks.entitlements`는 `project.yml`에서 생성되므로 커밋하지 않는다.
`App/Resources/web/app.js`는 `web/src/*.js`를 esbuild로 묶은 산출물이다. JS를 고치면 `make assets`로 다시 만든다.

## 개발 메모

- 렌더 시간 로그: `make logs` 후 문서를 연다. `render … ms`(Swift), `js ready`(DOM 후처리), `js enhanced`(하이라이팅·수식·다이어그램) 세 줄이 찍힌다. 보기 ▸ "렌더 통계 표시"로 창 안에서도 볼 수 있다.
- 디버그 빌드는 웹뷰 검사기가 켜져 있다. 문서 위에서 오른쪽 클릭 ▸ 요소 검사.
- 픽스처: `fixtures/kitchen-sink.md`를 열어 QLMarkdown(GitHub 테마)과 나란히 비교한다.

## 사용법 요약

- **워크스페이스**: ⌘N으로 폴더를 추가한다. 사이드바에 폴더를 끌어다 놓아도 된다. Finder에서 md 파일을 열면 그 폴더의 임시 워크스페이스가 생기고, 마지막 탭을 닫으면 사라진다(컨텍스트 메뉴 "고정"으로 유지).
- **탭·분할**: 파일 트리 단일 클릭은 미리보기 탭, 더블클릭은 고정 탭. ⌘D 오른쪽 분할, ⌘⇧D 아래 분할, ⌥⌘화살표로 패인 이동, ⌘W 탭 닫기.
- **찾기**: ⌘P 빠른 열기(파일), ⌘F 문서 안 찾기.
- **문서**: 파일을 저장하면 스크롤을 유지한 채 바뀐 부분만 갱신된다. 링크 ⌘클릭은 새 탭, ⌥클릭은 오른쪽 분할.
- 전체 단축키는 ⌘/ 로 본다. 설정은 ⌘,.

## 배포

```sh
make release
```

`build/release/cmarks-<버전>.zip`이 만들어진다. `Config/Local.xcconfig`(커밋되지 않음)에 `DEVELOPMENT_TEAM`과 `CODE_SIGN_IDENTITY = Developer ID Application`을 넣고, 공증 프로파일을 한 번 저장한 뒤 `CMARKS_NOTARY_PROFILE=cmarks make release`를 실행하면 Developer ID 서명·공증·스테이플까지 진행된다. 설정이 없으면 ad-hoc 서명 zip이 만들어지며, 받은 사람은 첫 실행 때 우클릭 ▸ 열기가 필요하다.

```sh
xcrun notarytool store-credentials cmarks --apple-id <Apple ID> --team-id <팀 ID> --password <앱 암호>
```

## 구조

| 경로 | 역할 |
|---|---|
| `App/` | SwiftUI 앱 타겟(셸, 사이드바, 레이아웃 UI, 웹뷰 호스트) |
| `Packages/MarkdownCore` | cmark-gfm 기반 렌더러, HTML 템플릿, 캐시 |
| `Packages/LayoutKit` | 워크스페이스 / 패인 트리 / 탭 모델과 연산, 세션 저장 |
| `Packages/FileKit` | 파일 접근 경계, 파일 감시, 파일 트리, fuzzy 매칭 |
| `web/` | 웹 자산 의존성(pnpm)과 JS 테스트 |
| `scripts/` | 에셋 벤더링, 설치, 배포(`release.sh`), CLI(`cmarks`) |
| `Config/` | 로컬 서명 설정(`Local.xcconfig`, 커밋 안 함)과 예시 |
