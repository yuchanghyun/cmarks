#!/usr/bin/env python3
"""appcast.xml에 릴리스 항목을 추가한다. release.sh가 호출한다.

사용: appcast.py --appcast appcast.xml --version 1.1.0 --build 3 --url https://…/cmarks-1.1.0.zip \
        --signature 'sparkle:edSignature="…" length="…"' --notes docs/RELEASE-NOTES.md [--min-os 15.0]

같은 버전 항목이 이미 있으면 교체하고, 새 항목은 맨 앞에 둔다. 릴리스 노트는 RELEASE-NOTES.md의
"## <version>" 절을 간단한 HTML(문단·목록·굵게·코드)로 바꿔 <description>에 넣는다.
"""
import argparse
import html
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import format_datetime
from datetime import datetime, timezone

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)


def notes_html(path: str, version: str) -> str:
    text = open(path, encoding="utf-8").read()
    m = re.search(r"^## " + re.escape(version) + r"\s*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        sys.exit(f"RELEASE-NOTES에 '## {version}' 절이 없다")
    def inline(s: str) -> str:
        s = html.escape(s, quote=False)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', s)
        return s
    out, items = [], []
    def flush():
        nonlocal items
        if items:
            out.append("<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>")
            items = []
    for line in m.group(1).splitlines():
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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--appcast", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--signature", required=True, help="sign_update 출력 한 줄")
    ap.add_argument("--notes", required=True)
    ap.add_argument("--min-os", default="15.0")
    ap.add_argument("--release-page")
    a = ap.parse_args()

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
    desc = ET.SubElement(item, "description")
    desc.text = "\n" + notes_html(a.notes, a.version) + "\n"
    enc = ET.SubElement(item, "enclosure")
    enc.set("url", a.url)
    enc.set("type", "application/octet-stream")
    enc.set("length", length.group(1))
    enc.set(f"{{{SPARKLE}}}edSignature", sig.group(1))

    first = channel.find("item")
    index = list(channel).index(first) if first is not None else len(channel)
    channel.insert(index, item)
    ET.indent(tree, space="  ")
    tree.write(a.appcast, encoding="utf-8", xml_declaration=True)
    lines = open(a.appcast, encoding="utf-8").read().split("\n")
    note = "<!-- Sparkle 업데이트 피드. scripts/release.sh가 릴리스마다 <item>을 맨 앞에 추가한다(scripts/appcast.py). 손으로 고치지 않는다. -->"
    if len(lines) > 1 and not lines[1].startswith("<!--"):
        lines.insert(1, note)
    open(a.appcast, "w", encoding="utf-8").write("\n".join(lines) + ("" if lines[-1] == "" else "\n"))
    print(f"appcast: {a.version} (build {a.build}) 추가")


if __name__ == "__main__":
    main()
