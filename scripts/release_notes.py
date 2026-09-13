#!/usr/bin/env python3
"""docs/RELEASE-NOTES.md에서 한 버전의 노트를 꺼낸다. 형식:

    ## 1.2.0
    - 한국어 항목 …
    ### English
    - English items …

사용:
  release_notes.py 1.2.0            GitHub 릴리스 본문(영어 먼저, 한국어 다음) 출력
  release_notes.py 1.2.0 --check    두 언어 절이 모두 있는지만 확인(없으면 종료 코드 1)
appcast.py가 이 모듈의 section()/to_html()을 가져다 쓴다.
"""
import html
import re
import sys
from pathlib import Path

NOTES = Path(__file__).resolve().parent.parent / "docs" / "RELEASE-NOTES.md"


def section(version: str, path: Path = NOTES) -> tuple[str, str]:
    """(한국어 마크다운, 영어 마크다운). 둘 중 하나라도 없으면 SystemExit."""
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^## " + re.escape(version) + r"\s*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        sys.exit(f"{path.name}에 '## {version}' 절이 없다")
    body = m.group(1)
    parts = re.split(r"^### English\s*\n", body, maxsplit=1, flags=re.M)
    ko = parts[0].strip()
    en = parts[1].strip() if len(parts) == 2 else ""
    if not ko or not en:
        sys.exit(f"'## {version}' 절에 한국어 항목과 '### English' 절이 모두 있어야 한다")
    return ko, en


def to_html(markdown: str) -> str:
    """항목·문단·굵게·코드·링크만 다루는 작은 변환기(Sparkle 설명란용)."""
    def inline(s: str) -> str:
        s = html.escape(s, quote=False)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', s)
        return s
    out: list[str] = []
    items: list[str] = []
    def flush() -> None:
        nonlocal items
        if items:
            out.append("<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>")
            items = []
    for line in markdown.splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            items.append(inline(line[2:]))
        elif line.startswith("### "):
            flush(); out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.strip():
            flush(); out.append(f"<p>{inline(line)}</p>")
        else:
            flush()
    flush()
    return "\n".join(out)


def github_body(version: str) -> str:
    ko, en = section(version)
    return f"{en}\n\n### 한국어\n\n{ko}\n"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if "--check" in sys.argv:
        section(sys.argv[1]); print(f"릴리스 노트 OK: {sys.argv[1]} (ko/en)")
    else:
        sys.stdout.write(github_body(sys.argv[1]))
