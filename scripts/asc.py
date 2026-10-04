#!/usr/bin/env python3
"""App Store Connect API 도우미. 업로드된 빌드를 버전에 붙이고 심사에 제출한다.

    python3 scripts/asc.py status                 # 앱·빌드·버전 상태
    python3 scripts/asc.py submit [--wait] [--dry-run] [--release-type AFTER_APPROVAL|MANUAL] [--version V --build N]
        project.yml의 버전(MARKETING_VERSION)과 빌드 번호(CURRENT_PROJECT_VERSION)로(--version/--build로 덧씌움):
        1) 빌드 처리 완료를 기다리고(--wait, 최대 45분)  2) App Store 버전을 찾거나 만들고  3) 빌드를 붙이고
        4) docs/RELEASE-NOTES.md의 한국어·영어 절을 "이번 버전의 새로운 기능"에 넣고  5) 심사에 제출한다.
        출시 방식 기본값은 AFTER_APPROVAL(승인되면 자동 출시). --dry-run은 읽기만 하고 쓰기 호출은 출력만 한다.
        이미 제출·출시된 버전이면 아무것도 바꾸지 않고 상태만 알린다(여러 번 실행해도 안전).

환경 변수: CMARKS_ASC_KEY_ID, CMARKS_ASC_ISSUER_ID, (선택) CMARKS_ASC_KEY_PATH. 키는 Admin 역할이어야 한다.
외부 라이브러리 없이 동작한다(JWT ES256 서명은 openssl로).
"""
import base64, json, os, re, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

BUNDLE_ID = "com.changhyunyoo.cmarks"
API = "https://api.appstoreconnect.apple.com"
ROOT = Path(__file__).resolve().parent.parent
LOCALES = {"ko": "ko", "en-US": "en"}  # App Store 로케일 → 릴리스 노트 절


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """openssl이 주는 DER ECDSA 서명(SEQUENCE{INTEGER r, INTEGER s})을 JWT용 raw r||s(64바이트)로."""
    assert sig[0] == 0x30
    i = 2
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        v = sig[i + 2 : i + 2 + n].lstrip(b"\x00")
        out += v.rjust(32, b"\x00")
        i += 2 + n
    return out


def token() -> str:
    key_id = os.environ.get("CMARKS_ASC_KEY_ID") or sys.exit("CMARKS_ASC_KEY_ID가 필요하다")
    issuer = os.environ.get("CMARKS_ASC_ISSUER_ID") or sys.exit("CMARKS_ASC_ISSUER_ID가 필요하다")
    key_path = os.environ.get("CMARKS_ASC_KEY_PATH") or str(Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8")
    if not Path(key_path).exists():
        sys.exit(f"API 키 파일이 없다: {key_path}")
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing_input, capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


_token_cache: dict = {}
DRY_RUN = False


def api(method: str, path: str, body=None, params=None):
    if DRY_RUN and method != "GET":
        print(f"  [dry-run] {method} {path} {json.dumps(body, ensure_ascii=False)[:160] if body else ''}")
        return {"data": {"id": "dry-run", "type": "dry-run", "attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION", "releaseType": "?"}}}
    if "value" not in _token_cache or _token_cache["at"] < time.time() - 10 * 60:
        _token_cache.update(value=token(), at=time.time())
    url = path if path.startswith("http") else API + path
    if params:
        url += ("&" if "?" in url else "?") + "&".join(f"{k}={urllib.request.quote(str(v), safe='')}" for k, v in params.items())
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {_token_cache['value']}", "Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        sys.exit(f"API {method} {path} → HTTP {e.code}\n{detail[:800]}")


def project_version() -> tuple[str, str]:
    text = (ROOT / "project.yml").read_text()
    version = re.search(r"^\s*MARKETING_VERSION:\s*(\S+)", text, re.M).group(1).strip('"')
    build = re.search(r"^\s*CURRENT_PROJECT_VERSION:\s*(\S+)", text, re.M).group(1).strip('"')
    return version, build


def whats_new(version: str) -> dict[str, str]:
    """RELEASE-NOTES.md의 '## <version>' 절에서 한국어 항목과 '### English' 항목을 App Store용 평문으로."""
    text = (ROOT / "docs/RELEASE-NOTES.md").read_text()
    m = re.search(rf"^## {re.escape(version)}\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        sys.exit(f"docs/RELEASE-NOTES.md에 '## {version}' 절이 없다")
    body = m.group(1)
    ko, _, en = body.partition("### English")

    def plain(section: str) -> str:
        lines = []
        for line in section.strip().splitlines():
            line = line.strip()
            if not line:
                continue
            line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)
            line = re.sub(r"`([^`]+)`", r"\1", line)
            line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
            lines.append(line)
        return "\n".join(lines)

    return {"ko": plain(ko), "en": plain(en)}


def vstate(v) -> str:
    a = v["attributes"]
    return a.get("appVersionState") or a.get("appStoreState") or "?"


def find_app() -> str:
    data = api("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not data:
        sys.exit(f"App Store Connect에 {BUNDLE_ID} 앱이 없다")
    return data[0]["id"]


def find_build(app_id: str, version: str, build: str):
    data = api("GET", "/v1/builds", params={
        "filter[app]": app_id, "filter[version]": build, "filter[preReleaseVersion.version]": version,
        "sort": "-uploadedDate", "limit": 5})["data"]
    return data[0] if data else None


def find_or_create_version(app_id: str, version: str, release_type: str):
    """versionString이 같은 버전을 찾고, 없으면 '제출 준비 중'인 버전의 이름을 바꿔 쓰고, 그것도 없으면 만든다.
    (App Store Connect는 첫 버전 말고는 버전을 지울 수 없어서 미리 만들어진 버전은 재사용한다.)"""
    data = api("GET", f"/v1/apps/{app_id}/appStoreVersions", params={
        "filter[platform]": "MAC_OS", "filter[versionString]": version, "limit": 5})["data"]
    if data:
        return data[0], False
    pending = [v for v in api("GET", f"/v1/apps/{app_id}/appStoreVersions", params={
        "filter[platform]": "MAC_OS", "filter[appVersionState]": "PREPARE_FOR_SUBMISSION", "limit": 5})["data"]]
    if pending:
        v = pending[0]
        print(f"제출 준비 중인 버전 {v['attributes']['versionString']}을(를) {version}으로 바꿔 쓴다")
        api("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"],
            "attributes": {"versionString": version, "releaseType": release_type}}})
        v["attributes"]["versionString"] = version
        v["attributes"]["releaseType"] = release_type
        return v, False
    created = api("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "MAC_OS", "versionString": version, "releaseType": release_type},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    return created["data"], True


def cmd_status():
    version, build = project_version()
    app_id = find_app()
    print(f"app: {app_id}  project.yml: {version} ({build})")
    builds = api("GET", "/v1/builds", params={"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5})["data"]
    for b in builds:
        a = b["attributes"]
        print(f"  build {a['version']}  {a['processingState']}  uploaded {a['uploadedDate'][:16]}")
    versions = api("GET", f"/v1/apps/{app_id}/appStoreVersions", params={"filter[platform]": "MAC_OS", "limit": 5})["data"]
    for v in versions:
        a = v["attributes"]
        print(f"  version {a['versionString']}  {vstate(v)}  release={a.get('releaseType')}  created {a.get('createdDate','')[:10]}")


def cmd_submit(wait: bool, release_type: str, version: str | None = None, build: str | None = None):
    pv, pb = project_version()
    version, build = version or pv, build or pb
    notes = whats_new(version)
    app_id = find_app()
    deadline = time.time() + 45 * 60
    while True:
        b = find_build(app_id, version, build)
        state = b["attributes"]["processingState"] if b else "(아직 없음)"
        if b and state == "VALID":
            break
        if b and state in ("FAILED", "INVALID"):
            sys.exit(f"빌드 {version} ({build}) 처리 실패: {state}")
        if not wait or time.time() > deadline:
            sys.exit(f"빌드 {version} ({build})가 아직 처리 중이다: {state}. 나중에 다시: make submit-appstore")
        print(f"빌드 {version} ({build}) 처리 중({state})… 30초 뒤 다시 확인", flush=True)
        time.sleep(30)
    print(f"빌드 {version} ({build}) 준비됨")

    ver, created = find_or_create_version(app_id, version, release_type)
    state = vstate(ver)
    print(f"App Store 버전 {version}: {'새로 만듦' if created else '있음'} ({state})")
    if state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE"):
        print("이미 심사에 제출되어 있다. 바꾸지 않는다.")
        return
    if state in ("ACCEPTED", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_DISTRIBUTION", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION"):
        print("이미 심사를 통과했거나 출시된 버전이다. 바꾸지 않는다.")
        return
    if state not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "READY_FOR_REVIEW"):
        sys.exit(f"버전 {version}은(는) {state} 상태라 이 스크립트가 다루지 않는다. App Store Connect에서 확인하라")

    current = api("GET", f"/v1/appStoreVersions/{ver['id']}/build")["data"] if not created else None
    if current and current["id"] == b["id"]:
        print(f"빌드 {build} 이미 연결됨")
    else:
        api("PATCH", f"/v1/appStoreVersions/{ver['id']}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        print(f"빌드 {build} 연결 완료")

    locs = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations", params={"limit": 20})["data"] if not DRY_RUN or not created else []
    for loc in locs:
        locale = loc["attributes"]["locale"]
        key = LOCALES.get(locale)
        if not key or not notes[key]:
            continue
        if (loc["attributes"].get("whatsNew") or "") == notes[key]:
            print(f"새로운 기능({locale}) 이미 같음")
            continue
        api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": notes[key]}}})
        print(f"새로운 기능({locale}) 입력")

    subs = api("GET", "/v1/reviewSubmissions", params={"filter[app]": app_id, "filter[platform]": "MAC_OS",
               "filter[state]": "READY_FOR_REVIEW,UNRESOLVED_ISSUES", "limit": 5})["data"]
    if subs:
        sub = subs[0]
        print(f"열려 있는 심사 제출 사용 ({sub['attributes']['state']})")
    else:
        sub = api("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "MAC_OS"},
                  "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("심사 제출 만듦")
    items = api("GET", f"/v1/reviewSubmissions/{sub['id']}/items", params={"limit": 20})["data"] if sub["id"] != "dry-run" else []
    if not any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == ver["id"] for i in items):
        api("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
        print("심사 항목에 버전 추가")
    api("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print(f"심사 제출 완료: {version} ({build}), 출시 방식 {ver['attributes'].get('releaseType')}")


def arg(args, name, default=None):
    return args[args.index(name) + 1] if name in args else default


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] == "status":
        cmd_status()
    elif args[0] == "submit":
        DRY_RUN = "--dry-run" in args
        cmd_submit(wait="--wait" in args, release_type=arg(args, "--release-type", "AFTER_APPROVAL"),
                   version=arg(args, "--version"), build=arg(args, "--build"))
    else:
        sys.exit(__doc__)
