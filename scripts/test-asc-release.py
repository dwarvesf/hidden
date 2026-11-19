#!/usr/bin/env python3
"""Offline tests for scripts/asc-release.py: argument parsing, the env-var checks, the listing.json
mapping, the ES256 token, and the dry-run write guard. No network, no 1Password, no Apple.
Run through scripts/test-release-mas.sh, or: python3 -I -B scripts/test-asc-release.py
One PASS/FAIL line per case; exit 0 only when no case failed."""
import base64
import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("asc_release", os.path.join(HERE, "asc-release.py"))
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)

PASSED, FAILED = 0, []
TMP = tempfile.mkdtemp(prefix="hb-asc-test.")
os.chmod(TMP, 0o755)


def case(fn):
    global PASSED
    try:
        fn()
        print("PASS " + fn.__name__)
        PASSED += 1
    except Exception as exc:  # noqa: BLE001 : a failing case must not stop the run
        print(f"FAIL {fn.__name__}: {type(exc).__name__}: {exc}")
        FAILED.append(fn.__name__)


def raises(exc_type, fn, *needles):
    try:
        fn()
    except exc_type as exc:
        for n in needles:
            assert n in str(exc), f"'{n}' not in '{exc}'"
        return
    raise AssertionError(f"{exc_type.__name__} not raised")


def make_key(name="k.p8"):
    path = os.path.join(TMP, name)
    ec = subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"], capture_output=True, check=True).stdout
    p8 = subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt"], input=ec, capture_output=True, check=True).stdout
    with open(path, "wb") as fh:
        fh.write(p8)
    return path


def make_pkg(mode=0o644, name="Hidden Bar.pkg"):
    d = tempfile.mkdtemp(prefix="pkg.", dir=TMP)
    os.chmod(d, 0o755)
    path = os.path.join(d, name)
    with open(path, "wb") as fh:
        fh.write(b"pkg")
    os.chmod(path, mode)
    return path


KEY = make_key()
ENV = {"HB_ASC_KEY_ID": "KEYID12345", "HB_ASC_ISSUER_ID": "issuer-uuid", "HB_ASC_KEY_FILE": KEY,
       "HB_COPYRIGHT": "2026 Test Holder", "HB_REVIEW_EMAIL": "review@example.test"}


class FakeASC:
    """A small stateful App Store Connect: enough routes for `release`, every call recorded."""

    def __init__(self, version=False, build=False, polls=("PROCESSING", "VALID")):
        self.calls, self.versions, self.uploaded, self.polls = [], [], build, list(polls)
        self.attrs, self.contact, self.build_attrs = {}, None, {"version": "22", "usesNonExemptEncryption": None}
        if version:
            self.versions.append(self._version("1.13.1"))

    @staticmethod
    def _version(ver):
        return {"id": "V1", "attributes": {"versionString": ver, "appVersionState": "PREPARE_FOR_SUBMISSION",
                                           "releaseType": "AFTER_APPROVAL", "copyright": "c"}}

    def call(self, method, path, body=None):
        self.calls.append((method, path, body))
        p, m = path.split("?")[0], method
        attrs = (body or {}).get("data", {}).get("attributes", {})
        if m == "GET" and p == "/v1/apps":
            return 200, {"data": [{"id": "A1"}]}
        if m == "GET" and p == "/v1/apps/A1/appStoreVersions":
            return 200, {"data": self.versions}
        if m == "GET" and p == "/v1/builds":
            if not self.uploaded:
                return 200, {"data": []}
            st = self.polls.pop(0) if len(self.polls) > 1 else self.polls[0]
            return 200, {"data": [{"id": "B1", "attributes": dict(self.build_attrs, processingState=st)}]}
        if m == "POST" and p == "/v1/appStoreVersions":
            self.versions.append(self._version(attrs["versionString"]))
            self.versions[-1]["attributes"].update(attrs)
            return 201, {"data": self.versions[-1]}
        if m == "PATCH" and p == "/v1/builds/B1":
            self.build_attrs.update(attrs)
            return 200, {}
        if p == "/v1/appStoreVersions/V1/relationships/build":
            return 200, {}
        if m == "GET" and p == "/v1/appStoreVersions/V1/build":
            return 200, {"data": {"attributes": {"version": "22"}}}
        if m == "GET" and p == "/v1/appStoreVersions/V1/appStoreReviewDetail":
            return 200, {"data": {"id": "D1", "attributes": self.contact} if self.contact else None}
        if m == "POST" and p == "/v1/appStoreReviewDetails":
            self.contact = attrs
            return 201, {}
        if m == "GET" and p == "/v1/appStoreVersions/V1/appStoreVersionLocalizations":
            return 200, {"data": [{"id": "L1", "attributes": {"locale": "en-US"}}]}
        if m == "GET" and p == "/v1/apps/A1/appInfos":
            return 200, {"data": [{"id": "I1", "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}}]}
        if m == "GET" and p == "/v1/appInfos/I1/appInfoLocalizations":
            return 200, {"data": [{"id": "L2", "attributes": {"locale": "en-US"}}]}
        if p in ("/v1/appStoreVersionLocalizations/L1", "/v1/appInfoLocalizations/L2"):
            if m == "PATCH":
                self.attrs.setdefault(p, {}).update(attrs)
                return 200, {}
            return 200, {"data": {"attributes": self.attrs.get(p, {})}}
        if m == "GET" and p == "/v1/reviewSubmissions":
            return 200, {"data": []}
        if m == "POST" and p == "/v1/reviewSubmissions":
            return 201, {"data": {"id": "S1234567"}}
        if m == "GET" and p == "/v1/reviewSubmissions/S1234567/items":
            return 200, {"data": []}
        if m == "POST" and p == "/v1/reviewSubmissionItems":
            return 201, {}
        if m == "PATCH" and p == "/v1/reviewSubmissions/S1234567":
            return 200, {"data": {"attributes": {"state": "WAITING_FOR_REVIEW"}}}
        raise AssertionError(f"FakeASC: unexpected {m} {path}")

    def writes(self):
        return [(m, p) for m, p, _ in self.calls if m != "GET"]


class FakeAltool:
    def __init__(self, asc=None, rc=0):
        self.calls, self.asc, self.rc, self.seen = [], asc, rc, []

    def __call__(self, argv, **kw):
        self.calls.append(argv)
        if argv[0] == "xcrun":
            d = kw["env"]["API_PRIVATE_KEYS_DIR"]
            f = os.path.join(d, "AuthKey_KEYID12345.p8")
            self.seen.append((stat.S_IMODE(os.stat(d).st_mode), stat.S_IMODE(os.stat(f).st_mode)))
            if self.asc and argv[2] == "--upload-app":
                self.asc.uploaded = True
            return subprocess.CompletedProcess(argv, self.rc, "UPLOAD SUCCEEDED\napiKey line\nissuer line", "")
        raise AssertionError(f"unexpected command {argv}")


def run_main(argv, env=None, asc=None, runner=None):
    out, err = io.StringIO(), io.StringIO()
    lines = []
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = R.main(argv, env=ENV if env is None else env, client_factory=lambda creds: asc,
                    runner=runner or FakeAltool(asc), out=lines.append, sleep=lambda s: None)
    return rc, "\n".join(lines) + out.getvalue(), err.getvalue()


def release_args(pkg, *extra):
    return ["release", "1.13.1", "22", "--pkg", pkg, *extra]


# ---- argument parsing -------------------------------------------------------------------------

def parse_release_flags():
    a = R.build_parser({}).parse_args(release_args("x.pkg", "--dry-run", "--copyright", "c", "--review-email", "e@x.test"))
    assert (a.cmd, a.version, a.build, a.pkg, a.dry_run, a.bundle, a.locale) == ("release", "1.13.1", "22", "x.pkg", True, "com.dwarvesv.minimalbar", "en-US")
    assert a.wait == 2700


def parse_wait_from_env():
    a = R.build_parser({"HB_BUILD_WAIT_SECONDS": "60"}).parse_args(["attach-build", "1.13.1", "22"])
    assert a.wait == 60


def parse_requires_pkg():
    with contextlib.redirect_stderr(io.StringIO()):
        raises(SystemExit, lambda: R.build_parser({}).parse_args(["release", "1.13.1", "22"]))


def parse_unknown_command():
    with contextlib.redirect_stderr(io.StringIO()):
        raises(SystemExit, lambda: R.build_parser({}).parse_args(["nope"]))


def version_and_build_shape():
    R.check_version_build("1.13.1", "22")
    raises(R.ToolError, lambda: R.check_version_build("1.13.1; rm", "22"), "not like")
    raises(R.ToolError, lambda: R.check_version_build("1.13.1", "2x"), "not an integer")


# ---- env-var checks ---------------------------------------------------------------------------

def creds_none_set():
    assert R.env_credentials({}) is None


def creds_all_set():
    c = R.env_credentials(ENV)
    assert (c.key_id, c.issuer, c.key_path) == ("KEYID12345", "issuer-uuid", KEY)


def creds_partial_refused():
    raises(R.ToolError, lambda: R.env_credentials({"HB_ASC_KEY_ID": "x"}), "all of HB_ASC_KEY_ID")


def creds_missing_key_file():
    raises(R.ToolError, lambda: R.env_credentials(dict(ENV, HB_ASC_KEY_FILE=os.path.join(TMP, "nope.p8"))), "not a file")


def missing_copyright_named_before_any_network():
    asc = FakeASC()
    rc, _, err = run_main(release_args(make_pkg()), env={k: v for k, v in ENV.items() if k != "HB_COPYRIGHT"}, asc=asc)
    assert rc == 1 and "HB_COPYRIGHT" in err and asc.calls == [], (rc, err, asc.calls)


def missing_review_email_named():
    rc, _, err = run_main(release_args(make_pkg()), env={k: v for k, v in ENV.items() if k != "HB_REVIEW_EMAIL"}, asc=FakeASC())
    assert rc == 1 and "HB_REVIEW_EMAIL" in err, (rc, err)


def flag_beats_env():
    a = R.build_parser({}).parse_args(["create-version", "1.13.1", "--copyright", "from flag"])
    assert R.need(a, {"HB_COPYRIGHT": "from env"}, "copyright", "HB_COPYRIGHT", "--copyright") == "from flag"


def partial_asc_env_stops_main_before_network():
    asc = FakeASC()
    rc, _, err = run_main(release_args(make_pkg(), "--dry-run"), env={"HB_ASC_KEY_ID": "x", "HB_COPYRIGHT": "c", "HB_REVIEW_EMAIL": "e"}, asc=asc)
    assert rc == 1 and "all of HB_ASC_KEY_ID" in err and asc.calls == [], (rc, err)


def root_only_pkg_refused():
    asc = FakeASC()
    rc, _, err = run_main(release_args(make_pkg(0o600)), asc=asc)
    assert rc == 1 and "90255" in err and asc.calls == [], (rc, err)


def world_readable_pkg_accepted():
    R.check_pkg(make_pkg(0o644))


def non_pkg_refused():
    raises(R.ToolError, lambda: R.check_pkg(KEY), "not a .pkg")


# ---- listing.json mapping ---------------------------------------------------------------------

LISTING = os.path.join(os.path.dirname(HERE), "docs", "appstore", "listing.json")


def listing_maps_to_asc_fields():
    vf, af, skipped = R.load_checked_listing(LISTING)
    assert set(vf) == {"description", "keywords", "promotionalText", "whatsNew", "supportUrl", "marketingUrl"}, set(vf)
    assert set(af) == {"subtitle", "privacyPolicyUrl"}, set(af)
    assert skipped == ["note"], skipped
    with open(LISTING) as fh:
        raw = json.load(fh)
    assert all(vf[k] == raw[k] for k in vf) and all(af[k] == raw[k] for k in af)


def listing_limits_count_bytes_for_keywords():
    assert R.over_limits({"keywords": "a" * 100}) == []
    assert R.over_limits({"keywords": "é" * 51}), "51 two-byte chars are 102 bytes"
    assert R.over_limits({"promotionalText": "x" * 171}) and not R.over_limits({"promotionalText": "x" * 170})
    assert R.over_limits({"subtitle": "x" * 31}) and R.over_limits({"description": "x" * 4001})


def listing_over_limit_refused_before_network():
    path = os.path.join(TMP, "long.json")
    with open(path, "w") as fh:
        json.dump({"subtitle": "x" * 31}, fh)
    asc = FakeASC()
    rc, _, err = run_main(release_args(make_pkg(), "--listing", path, "--dry-run"), asc=asc)
    assert rc == 1 and "subtitle is 31" in err and asc.calls == [], (rc, err)


def listing_non_string_refused():
    path = os.path.join(TMP, "bad.json")
    with open(path, "w") as fh:
        json.dump({"subtitle": 3}, fh)
    raises(R.ToolError, lambda: R.read_listing(path), "must be a string")


# ---- the ES256 token --------------------------------------------------------------------------

def raw_to_der(raw):
    def i(b):
        b = b.lstrip(b"\0") or b"\0"
        b = b"\0" + b if b[0] & 0x80 else b
        return bytes([2, len(b)]) + b
    body = i(raw[:32]) + i(raw[32:])
    return bytes([0x30, len(body)]) + body


def der_vectors():
    r, s = b"\x01" * 29, b"\xff" * 32
    der = bytes([0x30, 0x42, 2, 0x1D]) + r + bytes([2, 0x21, 0]) + s
    assert R.der_to_raw(der) == b"\0" * 3 + r + s
    raises(R.ToolError, lambda: R.der_to_raw(b"\x31" + b"\0" * 10), "unexpected")


def jwt_verifies_with_openssl():
    creds = R.Creds("KEYID12345", "issuer-uuid", KEY)
    token = R.make_jwt(creds, now=1_000_000)
    head, body, sig = token.split(".")

    def pad(t):
        return t + "=" * (-len(t) % 4)

    assert json.loads(base64.urlsafe_b64decode(pad(head))) == {"alg": "ES256", "kid": "KEYID12345", "typ": "JWT"}
    claims = json.loads(base64.urlsafe_b64decode(pad(body)))
    assert claims == {"iss": "issuer-uuid", "iat": 1_000_000, "exp": 1_000_900, "aud": "appstoreconnect-v1"}, claims
    raw = base64.urlsafe_b64decode(pad(sig))
    assert len(raw) == 64
    pub = subprocess.run(["openssl", "pkey", "-in", KEY, "-pubout"], capture_output=True, check=True).stdout
    pubf, sigf = os.path.join(TMP, "pub.pem"), os.path.join(TMP, "sig.der")
    with open(pubf, "wb") as fh:
        fh.write(pub)
    with open(sigf, "wb") as fh:
        fh.write(raw_to_der(raw))
    verify = ["openssl", "dgst", "-sha256", "-verify", pubf, "-signature", sigf]
    ok = subprocess.run(verify, input=f"{head}.{body}".encode(), capture_output=True)
    assert ok.returncode == 0, ok.stdout + ok.stderr
    bad = subprocess.run(verify, input=b"tampered", capture_output=True)
    assert bad.returncode != 0, "negative control: a tampered message must not verify"


# ---- dry-run and the full flow ----------------------------------------------------------------

def dry_run_writes_nothing_and_skips_altool():
    asc, altool = FakeASC(), FakeAltool()
    rc, out, err = run_main(release_args(make_pkg(), "--dry-run"), asc=asc, runner=altool)
    assert rc == 0, (rc, err)
    assert asc.writes() == [] and altool.calls == [], (asc.writes(), altool.calls)
    assert "would upload" in out and "would submit" in out and "stopped before upload and submit" in out, out


def readonly_guard_refuses_writes():
    ro = R.ReadOnly(FakeASC())
    assert ro.call("GET", "/v1/apps")[0] == 200
    for m in ("POST", "PATCH", "DELETE"):
        raises(R.DryRunWrite, lambda m=m: ro.call(m, "/v1/appStoreVersions", {}), "dry-run refused")


def dry_run_flag_is_what_protects():
    asc = FakeASC()
    altool = FakeAltool(asc)
    rc, out, err = run_main(release_args(make_pkg()), asc=asc, runner=altool)
    assert rc == 0 and altool.calls and asc.writes(), "negative control: without --dry-run the same call writes"


def full_flow_applies_the_lessons():
    asc = FakeASC()
    altool = FakeAltool(asc)
    rc, out, err = run_main(release_args(make_pkg()), asc=asc, runner=altool)
    assert rc == 0, (rc, out, err)
    flags = [c[2] for c in altool.calls]
    assert flags == ["--validate-app", "--upload-app"], flags
    assert all(d == 0o700 and f == 0o600 for d, f in altool.seen), altool.seen
    created = next(b for m, p, b in asc.calls if (m, p) == ("POST", "/v1/appStoreVersions"))["data"]["attributes"]
    assert created["releaseType"] == "AFTER_APPROVAL" and created["copyright"] == "2026 Test Holder", created
    assert asc.build_attrs["usesNonExemptEncryption"] is False
    assert asc.contact["contactEmail"] == "review@example.test"
    vf, af, _ = R.load_checked_listing(LISTING)
    assert all(asc.attrs["/v1/appStoreVersionLocalizations/L1"][k] == v for k, v in vf.items())
    assert all(asc.attrs["/v1/appInfoLocalizations/L2"][k] == v for k, v in af.items())
    submitted = [b for m, p, b in asc.calls if (m, p) == ("PATCH", "/v1/reviewSubmissions/S1234567")]
    assert len(submitted) == 1 and submitted[0]["data"]["attributes"] == {"submitted": True}, submitted
    assert "apiKey" not in out and "issuer line" not in out, "altool lines naming the key are filtered"


def rerun_skips_upload_and_existing_version():
    asc = FakeASC(version=True, build=True, polls=("VALID",))
    altool = FakeAltool(asc)
    rc, out, err = run_main(release_args(make_pkg()), asc=asc, runner=altool)
    assert rc == 0 and altool.calls == [], (rc, err)
    assert ("POST", "/v1/appStoreVersions") not in asc.writes()
    assert "upload skipped" in out and "exists already" in out, out


def altool_failure_stops_the_flow():
    asc = FakeASC()
    rc, out, err = run_main(release_args(make_pkg()), asc=asc, runner=FakeAltool(asc, rc=1))
    assert rc == 1 and "altool --validate-app failed" in err and asc.writes() == [], (rc, err, asc.writes())


def wait_for_build_paths():
    waits = []
    b = R.wait_for_build(FakeASC(build=True, polls=("PROCESSING", "PROCESSING", "VALID")), "A1", "1.13.1", "22", 600, waits.append, lambda s: None)
    assert b["attributes"]["processingState"] == "VALID" and waits == [30, 30]
    raises(R.ToolError, lambda: R.wait_for_build(FakeASC(build=True, polls=("INVALID",)), "A1", "1.13.1", "22", 600, lambda s: None, lambda s: None), "INVALID")
    raises(R.ToolError, lambda: R.wait_for_build(FakeASC(build=True, polls=("PROCESSING",)), "A1", "1.13.1", "22", 60, lambda s: None, lambda s: None), "after 60s")


def key_files_writes_a_private_key_and_prints_ids():
    d = tempfile.mkdtemp(prefix="kf.", dir=TMP)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = R.main(["key-files", d], env=ENV)
    f = os.path.join(d, "AuthKey_KEYID12345.p8")
    assert rc == 0 and buf.getvalue().strip() == "KEYID12345 issuer-uuid" and stat.S_IMODE(os.stat(f).st_mode) == 0o600


CASES = [parse_release_flags, parse_wait_from_env, parse_requires_pkg, parse_unknown_command, version_and_build_shape,
         creds_none_set, creds_all_set, creds_partial_refused, creds_missing_key_file,
         missing_copyright_named_before_any_network, missing_review_email_named, flag_beats_env,
         partial_asc_env_stops_main_before_network, root_only_pkg_refused, world_readable_pkg_accepted, non_pkg_refused,
         listing_maps_to_asc_fields, listing_limits_count_bytes_for_keywords, listing_over_limit_refused_before_network,
         listing_non_string_refused, der_vectors, jwt_verifies_with_openssl,
         dry_run_writes_nothing_and_skips_altool, readonly_guard_refuses_writes, dry_run_flag_is_what_protects,
         full_flow_applies_the_lessons, rerun_skips_upload_and_existing_version, altool_failure_stops_the_flow,
         wait_for_build_paths, key_files_writes_a_private_key_and_prints_ids]
for fn in CASES:
    case(fn)

print(f"\ntest-asc-release: {PASSED} passed, {len(FAILED)} failed" + (f" (failed: {' '.join(FAILED)})" if FAILED else ""))
sys.exit(1 if FAILED else 0)
