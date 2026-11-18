#!/usr/bin/env python3
"""App Store Connect release steps for Hidden Bar: upload the pkg, create the version, attach the
build, apply docs/appstore/listing.json, and submit for review. Standard library only (the ES256
token is signed with the system openssl), so there is nothing to install.

    asc-release.py release <version> <build> --pkg PKG --copyright TEXT --review-email EMAIL [--dry-run]
    asc-release.py state | upload PKG | create-version V --copyright T | attach-build V B
    asc-release.py review-contact V --email E | apply-listing V | submit V
    asc-release.py profile --cert-serial SERIAL | key-files DIR

`release` runs the steps in order and is safe to rerun: each step skips what already exists.
--dry-run does every offline check and every read (GET), writes nothing to App Store Connect, and
stops before upload and submit. Prints no key material.

Environment (docs/RUNBOOK.md, "App Store release"):
  HB_ASC_KEY_ID, HB_ASC_ISSUER_ID, HB_ASC_KEY_FILE  the API key, all three or none. With none, the
                                   key is read from 1Password (Connect first, then the ambient account).
  HB_OP_VAULT, HB_ASC_ITEM_SUFFIX  1Password vault and item-title suffix (dfoundation-prod, "Hacker Bar Release").
  HB_COPYRIGHT, HB_REVIEW_EMAIL    defaults for --copyright and --review-email.
  HB_BUILD_WAIT_SECONDS            how long attach-build waits for processing (default 2700).

Lessons this script encodes (App Store 1.13.1 run):
  - Export compliance: the build is marked "no non-exempt encryption" (usesNonExemptEncryption=false).
  - Release type is automatic after approval (AFTER_APPROVAL).
  - The pkg must be world-readable. A umask 077 build leaves files only root can read, which Apple
    rejects (error 90255); release-mas.sh checks the archived app, this script checks the pkg.
"""
import argparse
import base64
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.dwarvesv.minimalbar"
PLATFORM = "MAC_OS"
RELEASE_TYPE = "AFTER_APPROVAL"
DEFAULT_VAULT = "dfoundation-prod"
DEFAULT_ITEM_SUFFIX = "Hacker Bar Release"
CONNECT_HOST = "http://127.0.0.1:8090"
CONNECT_TOKEN_FILE = os.path.expanduser("~/op-connect/.connect-token")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_LISTING = os.path.join(ROOT, "docs", "appstore", "listing.json")
PROFILE_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
DEFAULT_WAIT = 2700
POLL_SECONDS = 30

# Apple's limits: (size, unit). Keywords count UTF-8 bytes, the rest characters.
LIMITS = {
    "subtitle": (30, "chars"),
    "keywords": (100, "bytes"),
    "promotionalText": (170, "chars"),
    "description": (4000, "chars"),
    "whatsNew": (4000, "chars"),
}
VERSION_FIELDS = ("description", "keywords", "promotionalText", "whatsNew", "supportUrl", "marketingUrl")
APPINFO_FIELDS = ("subtitle", "privacyPolicyUrl")
KNOWN_FIELDS = APPINFO_FIELDS + VERSION_FIELDS
EDITABLE_STATES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")
LIVE_STATES = ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")


class ToolError(Exception):
    """A user-facing failure: one line, exit 1, never a traceback."""


class DryRunWrite(ToolError):
    """A write was attempted while --dry-run was on."""


# ---- credentials ----------------------------------------------------------------------------

class Creds:
    def __init__(self, key_id, issuer, key_path):
        self.key_id, self.issuer, self.key_path = key_id, issuer, key_path


def env_credentials(env):
    """Creds from HB_ASC_* when all three are set, None when none is, ToolError on a partial set."""
    names = ("HB_ASC_KEY_ID", "HB_ASC_ISSUER_ID", "HB_ASC_KEY_FILE")
    got = {n: env.get(n, "") for n in names}
    n_set = sum(1 for v in got.values() if v)
    if n_set == 0:
        return None
    if n_set != 3:
        raise ToolError("set all of HB_ASC_KEY_ID, HB_ASC_ISSUER_ID, HB_ASC_KEY_FILE, or none (then 1Password is used)")
    if not os.path.isfile(got["HB_ASC_KEY_FILE"]):
        raise ToolError("HB_ASC_KEY_FILE is not a file")
    return Creds(got["HB_ASC_KEY_ID"], got["HB_ASC_ISSUER_ID"], got["HB_ASC_KEY_FILE"])


def _op_env(env):
    """Connect first when its heartbeat answers, else the ambient 1Password account."""
    e = dict(env)
    try:
        urllib.request.urlopen(CONNECT_HOST + "/heartbeat", timeout=3).read()
        with open(CONNECT_TOKEN_FILE) as fh:
            e["OP_CONNECT_HOST"], e["OP_CONNECT_TOKEN"] = CONNECT_HOST, fh.read().strip()
    except (OSError, urllib.error.URLError):
        e.pop("OP_CONNECT_HOST", None)
        e.pop("OP_CONNECT_TOKEN", None)
    return e


def write_private(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(text)


def onepassword_credentials(env, workdir, runner=subprocess.run):
    """Read the ASC key item from 1Password into workdir (mode 700). Prints nothing."""
    vault = env.get("HB_OP_VAULT") or DEFAULT_VAULT
    suffix = env.get("HB_ASC_ITEM_SUFFIX") or DEFAULT_ITEM_SUFFIX
    e = _op_env(env)

    def op(*a):
        p = runner(["op", *a, "--vault", vault, "--format", "json"], capture_output=True, text=True, env=e)
        if p.returncode != 0:
            raise ToolError(f"op {a[0]} {a[1]} failed (vault {vault})")
        return json.loads(p.stdout)

    try:
        ids = [i["id"] for i in op("item", "list") if i["title"].endswith(suffix)]
        if len(ids) != 1:
            raise ToolError(f"expected exactly one 1Password item titled '*{suffix}' in {vault}, found {len(ids)}")
        fields = op("item", "get", ids[0])["fields"]
    except FileNotFoundError:
        raise ToolError("no HB_ASC_* variables and no op CLI to read the key from 1Password") from None
    key_id = next((f.get("value") for f in fields if re.search(r"key ?id", f.get("label", ""), re.I)), None)
    issuer = next((f.get("value") for f in fields if re.search("issuer", f.get("label", ""), re.I)), None)
    pem = next((f.get("value") for f in fields if "BEGIN PRIVATE KEY" in (f.get("value") or "")), None)
    if not (key_id and issuer and pem):
        raise ToolError("the 1Password item lacks a private key, a key id or an issuer field")
    path = os.path.join(workdir, f"AuthKey_{key_id}.p8")
    write_private(path, pem)
    return Creds(key_id, issuer, path)


def resolve_credentials(env, workdir, runner=subprocess.run):
    return env_credentials(env) or onepassword_credentials(env, workdir, runner)


def wipe(path):
    try:
        open(path, "w").close()
    except OSError:
        pass


# ---- the ASC client -------------------------------------------------------------------------

def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(der, size=32):
    """An ECDSA DER signature (what openssl prints) to the raw r||s a JWT carries."""
    if len(der) < 8 or der[0] != 0x30:
        raise ToolError("unexpected signature encoding from openssl")
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        if der[i] != 0x02:
            raise ToolError("unexpected signature encoding from openssl")
        n = der[i + 1]
        value = der[i + 2:i + 2 + n].lstrip(b"\0")
        if len(value) > size:
            raise ToolError("signature integer too long")
        parts.append(value.rjust(size, b"\0"))
        i += 2 + n
    return b"".join(parts)


def make_jwt(creds, now=None, runner=subprocess.run):
    now = int(now if now is not None else time.time())
    head = b64url(json.dumps({"alg": "ES256", "kid": creds.key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64url(json.dumps({"iss": creds.issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                             separators=(",", ":")).encode())
    p = runner(["openssl", "dgst", "-sha256", "-sign", creds.key_path], input=f"{head}.{body}".encode(), capture_output=True)
    if p.returncode != 0:
        raise ToolError("openssl could not sign with the ASC key")
    return f"{head}.{body}.{b64url(der_to_raw(p.stdout))}"


class Client:
    def __init__(self, creds):
        self.creds, self._token, self._exp = creds, None, 0

    def call(self, method, path, body=None):
        """Return (status, json). Apple errors come back as {"errors": [...]}."""
        now = int(time.time())
        if self._token is None or now > self._exp - 60:
            self._token, self._exp = make_jwt(self.creds, now), now + 900
        req = urllib.request.Request(
            path if path.startswith("http") else API + path,
            data=json.dumps(body).encode() if body is not None else None, method=method,
            headers={"Authorization": "Bearer " + self._token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                raw = r.read()
                return r.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            try:
                errs = json.loads(e.read() or b"{}").get("errors", [])
            except ValueError:
                errs = []
            return e.code, {"errors": errs}
        except (urllib.error.URLError, TimeoutError) as e:
            raise ToolError(f"network error calling {method} {path.split('?')[0]}: {e}") from None


class ReadOnly:
    """Wraps a client for --dry-run: GET passes, every other method raises."""

    def __init__(self, inner):
        self.inner = inner

    def call(self, method, path, body=None):
        if method != "GET":
            raise DryRunWrite(f"dry-run refused {method} {path.split('?')[0]}")
        return self.inner.call(method, path, body)


def call(c, method, path, body=None):
    status, data = c.call(method, path, body)
    if status >= 300:
        errs = "; ".join(f"{e.get('code')}: {e.get('detail') or e.get('title')}" for e in data.get("errors", []))
        raise ToolError(f"{method} {path.split('?')[0]} -> {status}: {errs[:900]}")
    return data


# ---- App Store Connect lookups --------------------------------------------------------------

def state_of(attrs):
    return attrs.get("appVersionState") or attrs.get("appStoreState") or "UNKNOWN"


def app_id(c, bundle):
    d = call(c, "GET", f"/v1/apps?filter[bundleId]={bundle}")["data"]
    if len(d) != 1:
        raise ToolError(f"{len(d)} apps match {bundle}")
    return d[0]["id"]


def versions(c, aid):
    return call(c, "GET", f"/v1/apps/{aid}/appStoreVersions?filter[platform]={PLATFORM}&limit=50")["data"]


def find_version(c, aid, ver, required=True):
    hits = [v for v in versions(c, aid) if v["attributes"]["versionString"] == ver]
    if len(hits) > 1 or (required and not hits):
        raise ToolError(f"{len(hits)} {PLATFORM} versions named {ver}")
    return hits[0] if hits else None


def find_build(c, aid, ver, num):
    d = call(c, "GET", f"/v1/builds?filter[app]={aid}&filter[version]={num}&filter[preReleaseVersion.version]={ver}")["data"]
    if len(d) > 1:
        raise ToolError(f"{len(d)} builds {ver} ({num})")
    return d[0] if d else None


# ---- the pkg and the listing (offline) -------------------------------------------------------

def check_pkg(path):
    """The pkg exists and is world-readable (the umask 077 lesson; Apple error 90255)."""
    if not path.endswith(".pkg") or not os.path.isfile(path):
        raise ToolError(f"{path} is not a .pkg file")
    if not os.stat(path).st_mode & stat.S_IROTH:
        raise ToolError(f"{path} is not world-readable; a umask 077 build causes it (Apple error 90255)")
    parent = os.path.dirname(os.path.abspath(path))
    if os.stat(parent).st_mode & (stat.S_IROTH | stat.S_IXOTH) != (stat.S_IROTH | stat.S_IXOTH):
        raise ToolError(f"{parent} is not world-readable (Apple error 90255)")


def read_listing(path):
    try:
        with open(path, encoding="utf-8") as fh:
            listing = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ToolError(f"cannot read {path}: {exc}") from None
    if not isinstance(listing, dict):
        raise ToolError("listing.json must be a JSON object")
    for field in KNOWN_FIELDS:
        if field in listing and not isinstance(listing[field], str):
            raise ToolError(f"listing.json: {field} must be a string")
    return listing


def select_fields(listing):
    """Map listing.json to App Store Connect: (version-localization fields, app-info fields, skipped)."""
    version_fields = {f: listing[f] for f in VERSION_FIELDS if f in listing}
    appinfo_fields = {f: listing[f] for f in APPINFO_FIELDS if f in listing}
    skipped = [f for f in listing if f not in KNOWN_FIELDS]
    return version_fields, appinfo_fields, skipped


def over_limits(values):
    problems = []
    for field, value in values.items():
        limit, unit = LIMITS.get(field, (None, "chars"))
        size = len(value.encode("utf-8")) if unit == "bytes" else len(value)
        if limit is not None and size > limit:
            problems.append(f"{field} is {size} {unit}, Apple allows {limit}")
    return problems


def load_checked_listing(path):
    version_fields, appinfo_fields, skipped = select_fields(read_listing(path))
    problems = over_limits({**version_fields, **appinfo_fields})
    if problems:
        raise ToolError("listing over Apple's limits: " + "; ".join(problems))
    return version_fields, appinfo_fields, skipped


# ---- steps that write ------------------------------------------------------------------------

def run_altool(pkg, creds, runner=subprocess.run, out=print):
    """Validate, then upload, with altool. The key sits in a mode 700 temp dir for the calls only."""
    with tempfile.TemporaryDirectory(prefix="hb-altool.") as d:
        os.chmod(d, 0o700)
        key = os.path.join(d, f"AuthKey_{creds.key_id}.p8")
        with open(creds.key_path) as fh:
            write_private(key, fh.read())
        env = dict(os.environ, API_PRIVATE_KEYS_DIR=d)
        try:
            for flag in ("--validate-app", "--upload-app"):
                p = runner(["xcrun", "altool", flag, "-f", pkg, "-t", "macos", "--apiKey", creds.key_id,
                            "--apiIssuer", creds.issuer], capture_output=True, text=True, env=env)
                lines = [ln for ln in (p.stdout + p.stderr).splitlines()
                         if not re.search(r"apiKey|issuer|authenticationKey", ln, re.I)]
                out("\n".join(lines[-8:]))
                if p.returncode != 0:
                    raise ToolError(f"altool {flag} failed (exit {p.returncode})")
        finally:
            wipe(key)


def create_version(c, aid, ver, copyright_, out=print):
    if find_version(c, aid, ver, required=False):
        out(f"version {ver} exists already")
        return
    body = {"data": {"type": "appStoreVersions",
                     "attributes": {"platform": PLATFORM, "versionString": ver,
                                    "releaseType": RELEASE_TYPE, "copyright": copyright_},
                     "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}}
    a = call(c, "POST", "/v1/appStoreVersions", body)["data"]["attributes"]
    out(f"created {a['versionString']} {state_of(a)} release={a['releaseType']} copyright={a['copyright']!r}")


def wait_for_build(c, aid, ver, num, timeout, sleep=time.sleep, out=print):
    waited = 0
    while True:
        b = find_build(c, aid, ver, num)
        st = b["attributes"]["processingState"] if b else "NOT_LISTED_YET"
        if st == "VALID":
            return b
        if st in ("FAILED", "INVALID"):
            raise ToolError(f"build {ver} ({num}) processing {st}")
        if waited >= timeout:
            raise ToolError(f"build {ver} ({num}) is {st} after {waited}s; rerun attach-build later")
        out(f"build {ver} ({num}) {st}, waiting")
        sleep(POLL_SECONDS)
        waited += POLL_SECONDS


def attach_build(c, aid, ver, num, timeout, sleep=time.sleep, out=print):
    v = find_version(c, aid, ver)
    b = wait_for_build(c, aid, ver, num, timeout, sleep, out)
    if b["attributes"].get("usesNonExemptEncryption") is None:  # export compliance: no non-exempt encryption
        call(c, "PATCH", f"/v1/builds/{b['id']}",
             {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
        out("set usesNonExemptEncryption=false on the build")
    call(c, "PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    got = call(c, "GET", f"/v1/appStoreVersions/{v['id']}/build")["data"]
    out(f"attached build {got['attributes']['version']} to {ver}")


def review_contact(c, aid, ver, email, out=print):
    v = find_version(c, aid, ver)
    cur = call(c, "GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")["data"]
    if cur:
        call(c, "PATCH", f"/v1/appStoreReviewDetails/{cur['id']}",
             {"data": {"type": "appStoreReviewDetails", "id": cur["id"], "attributes": {"contactEmail": email}}})
    else:
        prev = {}  # carry the rest of the contact from the live version's review detail
        for pv in versions(c, aid):
            if state_of(pv["attributes"]) in LIVE_STATES:
                pd = call(c, "GET", f"/v1/appStoreVersions/{pv['id']}/appStoreReviewDetail")["data"]
                if pd:
                    prev = pd["attributes"]
                    break
        attrs = {k: prev.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone",
                                          "demoAccountRequired", "notes") if prev.get(k) is not None}
        attrs["contactEmail"] = email
        attrs.setdefault("demoAccountRequired", False)
        call(c, "POST", "/v1/appStoreReviewDetails",
             {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                       "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    got = call(c, "GET", f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")["data"]["attributes"]
    out(f"review contact email={got['contactEmail']} name_set={bool(got.get('contactFirstName'))} phone_set={bool(got.get('contactPhone'))}")


def localization(c, parent_path, locale):
    for loc in call(c, "GET", f"{parent_path}?limit=200")["data"]:
        if loc["attributes"].get("locale") == locale:
            return loc
    return None


def patch_fields(c, resource_type, rid, fields, out=print):
    """PATCH each field on its own so a 409 names the field, then read back. True when all matched."""
    path, ok, patched = f"/v1/{resource_type}/{rid}", True, []
    for field, value in fields.items():
        status, data = c.call("PATCH", path, {"data": {"type": resource_type, "id": rid, "attributes": {field: value}}})
        if status >= 300:
            ok = False
            out(f"  FAIL HTTP {status} {field}: " + "; ".join(str(e.get("detail") or e.get("title")) for e in data.get("errors", [])))
        else:
            patched.append(field)
    if patched:
        got = call(c, "GET", path)["data"]["attributes"]
        for field in patched:
            same = (got.get(field) or "") == fields[field]
            ok &= same
            out(f"  {'ok  ' if same else 'DIFF'} {field} {'matches listing' if same else 'DIFFERS from listing'}")
    return ok


def apply_listing(c, aid, ver, version_fields, appinfo_fields, locale, out=print):
    v = find_version(c, aid, ver)
    if state_of(v["attributes"]) not in EDITABLE_STATES:
        raise ToolError(f"version {ver} is {state_of(v['attributes'])}, not editable")
    ok = True
    loc = localization(c, f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", locale)
    if loc is None:
        raise ToolError(f"version {ver} has no {locale} localization")
    out(f"version localization {locale}:")
    ok &= patch_fields(c, "appStoreVersionLocalizations", loc["id"], version_fields, out)
    infos = call(c, "GET", f"/v1/apps/{aid}/appInfos")["data"]
    info = next((i for i in infos if (i["attributes"].get("appStoreState") or i["attributes"].get("state")) in EDITABLE_STATES), None)
    if info is None:
        out("  skipped app-info fields: no editable app-info")
    else:
        iloc = localization(c, f"/v1/appInfos/{info['id']}/appInfoLocalizations", locale)
        if iloc is None:
            raise ToolError(f"editable app-info has no {locale} localization")
        out(f"app-info localization {locale}:")
        ok &= patch_fields(c, "appInfoLocalizations", iloc["id"], appinfo_fields, out)
    if not ok:
        raise ToolError("the listing did not apply cleanly (see above)")


def submit(c, aid, ver, out=print):
    v = find_version(c, aid, ver)
    open_subs = call(c, "GET", f"/v1/reviewSubmissions?filter[app]={aid}&filter[platform]={PLATFORM}&filter[state]=READY_FOR_REVIEW")["data"]
    sid = open_subs[0]["id"] if open_subs else call(c, "POST", "/v1/reviewSubmissions", {
        "data": {"type": "reviewSubmissions", "attributes": {"platform": PLATFORM},
                 "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]["id"]
    if not call(c, "GET", f"/v1/reviewSubmissions/{sid}/items")["data"]:
        call(c, "POST", "/v1/reviewSubmissionItems", {
            "data": {"type": "reviewSubmissionItems",
                     "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                                       "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    d = call(c, "PATCH", f"/v1/reviewSubmissions/{sid}",
             {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    out(f"submission {sid[:8]} {d['data']['attributes'].get('state')}")
    out(f"version {ver}: {state_of(find_version(c, aid, ver)['attributes'])}")


# ---- commands --------------------------------------------------------------------------------

def need(args, env, attr, var, flag):
    value = getattr(args, attr, None) or env.get(var, "")
    if not value:
        raise ToolError(f"missing {flag} (or {var})")
    return value


def check_version_build(ver, build=None):
    if not re.fullmatch(r"\d+(\.\d+){1,2}", ver):
        raise ToolError(f"version '{ver}' is not like 1.13.1")
    if build is not None and not re.fullmatch(r"\d+", build):
        raise ToolError(f"build '{build}' is not an integer")


def cmd_state(c, a, env, out=print):
    aid = app_id(c, a.bundle)
    out(f"app {a.bundle}")
    for v in versions(c, aid)[:6]:
        at = v["attributes"]
        out(f"  version {at['versionString']}: {state_of(at)} release={at.get('releaseType')} copyright={at.get('copyright')!r}")
    d = call(c, "GET", f"/v1/builds?filter[app]={aid}&sort=-uploadedDate&limit=10&include=preReleaseVersion")
    pre = {x["id"]: x["attributes"]["version"] for x in d.get("included", []) if x["type"] == "preReleaseVersions"}
    for b in d["data"]:
        at = b["attributes"]
        pr = (b["relationships"].get("preReleaseVersion", {}).get("data") or {}).get("id")
        out(f"  build {pre.get(pr, '?')} ({at['version']}) {at['processingState']} uploaded {at['uploadedDate']} encryption={at.get('usesNonExemptEncryption')}")
    for s in call(c, "GET", f"/v1/reviewSubmissions?filter[app]={aid}&filter[platform]={PLATFORM}&limit=5")["data"]:
        out(f"  reviewSubmission {s['id'][:8]} {s['attributes'].get('state')} {s['attributes'].get('submittedDate')}")
    return 0


def cmd_profile(c, a, env, out=print):
    """Download an active MAC_APP_STORE profile for the bundle holding the cert with --cert-serial, or create one."""
    bids = [b for b in call(c, "GET", f"/v1/bundleIds?filter[identifier]={a.bundle}&limit=20")["data"]
            if b["attributes"]["identifier"] == a.bundle]
    if len(bids) != 1:
        raise ToolError(f"{len(bids)} bundle ids equal {a.bundle}")
    certs = [x for x in call(c, "GET", "/v1/certificates?limit=200")["data"]
             if (x["attributes"].get("serialNumber") or "").upper() == a.cert_serial.upper()]
    if len(certs) != 1:
        raise ToolError(f"{len(certs)} certificates have serial {a.cert_serial}")
    prof = None
    for p in call(c, "GET", f"/v1/bundleIds/{bids[0]['id']}/profiles?limit=50")["data"]:
        at = p["attributes"]
        if at["profileType"] == "MAC_APP_STORE" and at["profileState"] == "ACTIVE":
            if certs[0]["id"] in {x["id"] for x in call(c, "GET", f"/v1/profiles/{p['id']}/certificates")["data"]}:
                prof = call(c, "GET", f"/v1/profiles/{p['id']}")["data"]
                out("reused active profile")
                break
    if prof is None:
        prof = call(c, "POST", "/v1/profiles", {"data": {"type": "profiles",
                    "attributes": {"name": a.name, "profileType": "MAC_APP_STORE"},
                    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bids[0]["id"]}},
                                      "certificates": {"data": [{"type": "certificates", "id": certs[0]["id"]}]}}}})["data"]
        out("created profile")
    at = prof["attributes"]
    dest = a.out or os.path.join(PROFILE_DIR, f"{at['uuid']}.provisionprofile")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(base64.b64decode(at["profileContent"]))
    out(f"profile name={at['name']!r} uuid={at['uuid']} expires={at.get('expirationDate')} -> {dest}")
    out("set HB_MAS_PROFILE to that name or uuid")
    return 0


def cmd_upload(a, creds, out=print, runner=subprocess.run):
    if a.dry_run:
        out(f"dry-run: pkg ok, would run altool --validate-app then --upload-app on {a.pkg}")
        return 0
    run_altool(a.pkg, creds, runner, out)
    return 0


def cmd_create_version(c, a, env, out=print):
    create_version(c, app_id(c, a.bundle), a.version, need(a, env, "copyright", "HB_COPYRIGHT", "--copyright"), out)
    return 0


def cmd_attach_build(c, a, env, out=print, sleep=time.sleep):
    attach_build(c, app_id(c, a.bundle), a.version, a.build, a.wait, sleep, out)
    return 0


def cmd_review_contact(c, a, env, out=print):
    review_contact(c, app_id(c, a.bundle), a.version, need(a, env, "email", "HB_REVIEW_EMAIL", "--email"), out)
    return 0


def cmd_apply_listing(c, a, env, out=print):
    vf, af, skipped = load_checked_listing(a.listing)
    apply_listing(c, app_id(c, a.bundle), a.version, vf, af, a.locale, out)
    out("skipped (not App Store Connect fields): " + ", ".join(skipped) if skipped else "nothing skipped")
    return 0


def cmd_submit(c, a, env, out=print):
    submit(c, app_id(c, a.bundle), a.version, out)
    return 0


def cmd_release(c, a, creds, out=print, runner=subprocess.run, sleep=time.sleep):
    """Every step in order. --dry-run: offline checks and GET reads only; stops before upload and submit."""
    vf, af, skipped = load_checked_listing(a.listing)
    aid = app_id(c, a.bundle)
    version = find_version(c, aid, a.version, required=False)
    build = find_build(c, aid, a.version, a.build)
    out(f"app {a.bundle}: version {a.version} " + (f"exists ({state_of(version['attributes'])})" if version else "not created yet")
        + f", build {a.build} " + (f"already uploaded ({build['attributes']['processingState']})" if build else "not uploaded yet"))
    if a.dry_run:
        plan = [("upload", f"altool validate + upload {a.pkg}", build is not None),
                ("create version", f"{a.version}, release type {RELEASE_TYPE}, copyright {a.copyright!r}", version is not None),
                ("attach build", f"{a.build} once processed, export compliance: no non-exempt encryption", False),
                ("review contact", a.review_email, False),
                ("apply listing", f"{', '.join(list(vf) + list(af))} ({a.locale}); not fields: {', '.join(skipped) or 'none'}", False),
                ("submit", f"version {a.version} for review", False)]
        for name, what, done in plan:
            out(f"dry-run: would {name}: {what}" + (" (already done, skipped)" if done else ""))
        out("dry-run: nothing written to App Store Connect; stopped before upload and submit")
        return 0
    if build is None:
        run_altool(a.pkg, creds, runner, out)
    else:
        out(f"upload skipped: build {a.build} is already on App Store Connect")
    create_version(c, aid, a.version, a.copyright, out)
    attach_build(c, aid, a.version, a.build, a.wait, sleep, out)
    review_contact(c, aid, a.version, a.review_email, out)
    apply_listing(c, aid, a.version, vf, af, a.locale, out)
    submit(c, aid, a.version, out)
    return 0


def build_parser(env=None):
    env = os.environ if env is None else env
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--bundle", default=BUNDLE_ID)
    common.add_argument("--locale", default="en-US")
    common.add_argument("--dry-run", action="store_true", help="read and check only; write nothing")
    wait_default = int(env.get("HB_BUILD_WAIT_SECONDS") or DEFAULT_WAIT)
    p = argparse.ArgumentParser(prog="asc-release.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    def add(name):
        return sub.add_parser(name, parents=[common])

    add("state")
    s = add("key-files"); s.add_argument("dir")
    s = add("profile"); s.add_argument("--cert-serial", required=True); s.add_argument("--name", default="Hidden Bar MAS"); s.add_argument("--out")
    s = add("upload"); s.add_argument("pkg")
    s = add("create-version"); s.add_argument("version"); s.add_argument("--copyright")
    s = add("attach-build"); s.add_argument("version"); s.add_argument("build"); s.add_argument("--wait", type=int, default=wait_default)
    s = add("review-contact"); s.add_argument("version"); s.add_argument("--email")
    s = add("apply-listing"); s.add_argument("version"); s.add_argument("--listing", default=DEFAULT_LISTING)
    s = add("submit"); s.add_argument("version")
    s = add("release")
    s.add_argument("version"); s.add_argument("build"); s.add_argument("--pkg", required=True)
    s.add_argument("--copyright"); s.add_argument("--review-email"); s.add_argument("--listing", default=DEFAULT_LISTING)
    s.add_argument("--wait", type=int, default=wait_default)
    return p


def check_offline(a, env):
    """Every check that needs no credential and no network; raises ToolError before either is touched."""
    if hasattr(a, "version"):
        check_version_build(a.version, getattr(a, "build", None))
    if a.cmd in ("create-version", "release"):
        a.copyright = need(a, env, "copyright", "HB_COPYRIGHT", "--copyright")
    if a.cmd == "review-contact":
        a.email = need(a, env, "email", "HB_REVIEW_EMAIL", "--email")
    if a.cmd == "release":
        a.review_email = need(a, env, "review_email", "HB_REVIEW_EMAIL", "--review-email")
    if a.cmd in ("upload", "release"):
        check_pkg(a.pkg)
    if a.cmd in ("apply-listing", "release"):
        load_checked_listing(a.listing)


def main(argv=None, env=None, client_factory=Client, runner=subprocess.run, out=print, sleep=time.sleep):
    env = os.environ if env is None else env
    a = build_parser(env).parse_args(argv)
    workdir = None
    try:
        check_offline(a, env)
        if a.cmd == "upload" and a.dry_run:
            return cmd_upload(a, None, out, runner)
        workdir = tempfile.mkdtemp(prefix="hb-asc.")
        os.chmod(workdir, 0o700)
        creds = resolve_credentials(env, workdir, runner)
        if a.cmd == "key-files":
            with open(creds.key_path) as fh:
                write_private(os.path.join(a.dir, f"AuthKey_{creds.key_id}.p8"), fh.read())
            print(f"{creds.key_id} {creds.issuer}")
            return 0
        if a.cmd == "upload":
            return cmd_upload(a, creds, out, runner)
        c = client_factory(creds)
        if a.dry_run:
            c = ReadOnly(c)
        if a.cmd == "release":
            return cmd_release(c, a, creds, out, runner, sleep)
        if a.cmd == "attach-build":
            return cmd_attach_build(c, a, env, out, sleep)
        handler = {"state": cmd_state, "profile": cmd_profile, "create-version": cmd_create_version,
                   "review-contact": cmd_review_contact, "apply-listing": cmd_apply_listing, "submit": cmd_submit}[a.cmd]
        return handler(c, a, env, out)
    except ToolError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    finally:
        if workdir:
            for f in os.listdir(workdir):
                wipe(os.path.join(workdir, f))
            shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
