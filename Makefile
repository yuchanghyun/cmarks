# cmarks 개발용 Makefile.
SCHEME   := cmarks
CONFIG   ?= Debug
DERIVED  := build
PROJECT  := cmarks.xcodeproj
APP      := $(DERIVED)/Build/Products/$(CONFIG)/cmarks.app
PACKAGES := Packages/MarkdownCore Packages/LayoutKit Packages/FileKit
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED)

.PHONY: gen build run test test-packages test-web test-app assets icon install release logs clean

gen:                ## project.yml → cmarks.xcodeproj (로컬 서명 설정 파일이 없으면 예시로 만든다)
	@[ -f Config/Local.xcconfig ] || cp Config/Local.xcconfig.example Config/Local.xcconfig
	xcodegen generate

build: gen          ## 앱 빌드 (CONFIG=Debug|Release)
	$(XCB) -configuration $(CONFIG) build -quiet

run: build          ## 빌드 후 실행
	open $(APP)

test: test-packages test-web test-app

test-packages:      ## SwiftPM 패키지 테스트 (Xcode 프로젝트 불필요)
	@for p in $(PACKAGES); do echo "== $$p"; (cd $$p && swift test) || exit 1; done

test-app: gen       ## 앱 타겟 테스트
	$(XCB) -destination 'platform=macOS' test 2>&1 | grep -E '^(Test Suite|\s*Executed|✔|✘|\*\* TEST|.*error:)' | grep -v 'Executed 0 tests'

assets:             ## 웹 의존성 설치 + vendor 갱신 + app.js 번들
	cd web && pnpm install && pnpm vendor && pnpm build

test-web:           ## JS 후처리 테스트 (vitest)
	cd web && pnpm test

icon:               ## 앱 아이콘 생성 (cmux처럼 밝은 바탕 + 파란 그라데이션 c)
	swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

install:            ## /Applications에 설치 (공증본이 있으면 그것을, 없으면 Release 빌드를 재서명해서)
	bash scripts/install.sh

release:            ## 직접 배포용 zip·DMG (Developer ID + 공증 설정이 있으면 공증까지)
	bash scripts/release.sh

logs:               ## 앱 로그 실시간 보기 (zsh의 log 내장 명령과 겹쳐 절대 경로 사용)
	/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.changhyunyoo.cmarks"'

clean:
	rm -rf $(DERIVED) $(PROJECT)
	@for p in $(PACKAGES); do rm -rf $$p/.build; done
