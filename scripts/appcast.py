#!/usr/bin/env python3
"""appcast.xml에 릴리스 항목을 추가한다. release.sh가 호출한다.

사용: appcast.py --appcast appcast.xml --version 1.1.0 --build 3 --url https://…/cmarks-1.1.0.zip \
        --signature 'sparkle:edSignature="…" length="…"' --notes docs/RELEASE-NOTES.md [--min-os 15.0]

같은 버전 항목이 이미 있으면 교체하고, 새 항목은 맨 앞에 둔다. 릴리스 노트는 RELEASE-NOTES.md의
"## <version>" 절을 간단한 HTML(문단·목록·굵게·코드)로 바꿔 <description>에 넣는다.
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.dont_write_bytecode = True   # 저장소 안에 __pycache__를 만들지 않는다
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_notes import section, to_html  # noqa: E402
from email.utils import format_datetime
from datetime import datetime, timezone

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
XML = "http://www.w3.org/XML/1998/namespace"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)


def set_descriptions(item: ET.Element, version: str, notes: Path) -> None:
    """Sparkle은 xml:lang이 사용자 언어와 맞는 <description>을 고르고, 없으면 언어 표시가 없는 것을 쓴다.
    영어(기본)·한국어·영어(fallback) 순으로 넣는다."""
    for old in item.findall("description"):
        item.remove(old)
    ko, en = section(version, notes)
    anchor = item.find("enclosure")
    index = list(item).index(anchor) if anchor is not None else len(item)
    for lang, md in (("en", en), ("ko", ko), (None, en)):
        d = ET.Element("description")
        if lang:
            d.set(f"{{{XML}}}lang", lang)
        d.text = "\n" + to_html(md) + "\n"
        item.insert(index, d); index += 1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--appcast", required=True)
    ap.add_argument("--notes", required=True)
    ap.add_argument("--refresh-notes", action="store_true", help="기존 항목들의 설명만 릴리스 노트에서 다시 만든다")
    ap.add_argument("--version")
    ap.add_argument("--build")
    ap.add_argument("--url")
    ap.add_argument("--signature", help="sign_update 출력 한 줄")
    ap.add_argument("--min-os", default="15.0")
    ap.add_argument("--release-page")
    a = ap.parse_args()

    if a.refresh_notes:
        tree = ET.parse(a.appcast)
        for item in tree.getroot().find("channel").findall("item"):
            set_descriptions(item, item.findtext(f"{{{SPARKLE}}}shortVersionString"), Path(a.notes))
        write(tree, a.appcast)
        print("appcast: 기존 항목 설명 갱신")
        return
    for name in ("version", "build", "url", "signature"):
        if not getattr(a, name):
            sys.exit(f"--{name} 이 필요하다")

    sig = re.search(r'sparkle:edSignature="([^"]+)"', a.signature)
    length = re.search(r'length="(\d+)"', a.signature)
    if not sig or not length:
        sys.exit(f"서명 문자열을 해석할 수 없다: {a.signature!r}")

    tree = ET.parse(a.appcast)
    channel = tree.getroot().find("channel")
    for old in channel.findall("item"):
        if old.findtext(f"{{{SPARKLE}}}shortVersionString") == a.version:
            channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"cmarks {a.version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = a.build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = a.version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = a.min_os
    if a.release_page:
        ET.SubElement(item, "link").text = a.release_page
    enc = ET.SubElement(item, "enclosure")
    enc.set("url", a.url)
    enc.set("type", "application/octet-stream")
    enc.set("length", length.group(1))
    enc.set(f"{{{SPARKLE}}}edSignature", sig.group(1))

    set_descriptions(item, a.version, Path(a.notes))
    first = channel.find("item")
    index = list(channel).index(first) if first is not None else len(channel)
    channel.insert(index, item)
    write(tree, a.appcast)
    print(f"appcast: {a.version} (build {a.build}) 추가")


def write(tree: ET.ElementTree, path: str) -> None:
    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    lines = open(path, encoding="utf-8").read().split("\n")
    note = "<!-- Sparkle 업데이트 피드. scripts/release.sh가 릴리스마다 <item>을 맨 앞에 추가한다(scripts/appcast.py). 손으로 고치지 않는다. -->"
    if len(lines) > 1 and not lines[1].startswith("<!--"):
        lines.insert(1, note)
    open(path, "w", encoding="utf-8").write("\n".join(lines) + ("" if lines[-1] == "" else "\n"))


if __name__ == "__main__":
    main()
