#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RC_VERSION="${HERMES_RC_VERSION:-0.1.0-rc.1}"
SAFE_VERSION="$(printf '%s' "$RC_VERSION" | tr -c 'A-Za-z0-9._-' '-')"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m12-002"
WORK_ROOT="$ARTIFACT_DIR/worktrees"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
PROVENANCE_FILE="$ARTIFACT_DIR/provenance.json"
INVENTORY_A="$ARTIFACT_DIR/inventory-a.json"
INVENTORY_B="$ARTIFACT_DIR/inventory-b.json"
DIFFERENCES_FILE="$ARTIFACT_DIR/differences.json"
SOURCE_COMMIT="${HERMES_SOURCE_COMMIT:-}"
SOURCE_BRANCH="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || print detached)"

typeset -A RESULT

ORDERED_KEYS=(
  SOURCE_COMMIT_FIXED CLEAN_BUILD_A CLEAN_BUILD_B BUILD_A_RC_CREATED BUILD_B_RC_CREATED
  RC_VERSION_MATCH SOURCE_COMMIT_MATCH PAYLOAD_TOPOLOGY_MATCH NORMALIZED_PAYLOAD_MATCH
  UNEXPLAINED_DIFFERENCES INVENTORY_A_CREATED INVENTORY_B_CREATED INVENTORIES_MATCH
  PROVENANCE_CREATED PROVENANCE_SOURCE_RECORDED PROVENANCE_OUTPUT_HASHES_RECORDED
  MANIFEST_CONSISTENT SBOM_CONSISTENT CHECKSUMS_CONSISTENT APP_SERVICE_VERSION_CONSISTENT
  XPC_PROTOCOL_1_7 PRODUCTION_COMPONENTS_ONLY ACCEPTANCE_SUPPORT_INCLUDED
  TEST_COMPONENT_INCLUDED DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED
  ISOLATED_WORKTREES_CLEANED RESIDUAL_PROCESS READY_FOR_SIGNING_PROMOTION M12_002_RESULT
)

set_default_results() {
  RESULT=(
    SOURCE_COMMIT_FIXED no
    CLEAN_BUILD_A no
    CLEAN_BUILD_B no
    BUILD_A_RC_CREATED no
    BUILD_B_RC_CREATED no
    RC_VERSION_MATCH no
    SOURCE_COMMIT_MATCH no
    PAYLOAD_TOPOLOGY_MATCH no
    NORMALIZED_PAYLOAD_MATCH no
    UNEXPLAINED_DIFFERENCES yes
    INVENTORY_A_CREATED no
    INVENTORY_B_CREATED no
    INVENTORIES_MATCH no
    PROVENANCE_CREATED no
    PROVENANCE_SOURCE_RECORDED no
    PROVENANCE_OUTPUT_HASHES_RECORDED no
    MANIFEST_CONSISTENT no
    SBOM_CONSISTENT no
    CHECKSUMS_CONSISTENT no
    APP_SERVICE_VERSION_CONSISTENT no
    XPC_PROTOCOL_1_7 no
    PRODUCTION_COMPONENTS_ONLY no
    ACCEPTANCE_SUPPORT_INCLUDED yes
    TEST_COMPONENT_INCLUDED yes
    DEVELOPER_PATH_EXPOSED yes
    TOKEN_EXPOSED yes
    PRIVATE_KEY_EXPOSED yes
    ISOLATED_WORKTREES_CLEANED no
    RESIDUAL_PROCESS yes
    READY_FOR_SIGNING_PROMOTION no
    M12_002_RESULT FAIL
  )
}

write_result() {
  local pass="yes"
  for key in \
    SOURCE_COMMIT_FIXED CLEAN_BUILD_A CLEAN_BUILD_B BUILD_A_RC_CREATED BUILD_B_RC_CREATED \
    RC_VERSION_MATCH SOURCE_COMMIT_MATCH PAYLOAD_TOPOLOGY_MATCH NORMALIZED_PAYLOAD_MATCH \
    INVENTORY_A_CREATED INVENTORY_B_CREATED INVENTORIES_MATCH PROVENANCE_CREATED \
    PROVENANCE_SOURCE_RECORDED PROVENANCE_OUTPUT_HASHES_RECORDED MANIFEST_CONSISTENT \
    SBOM_CONSISTENT CHECKSUMS_CONSISTENT APP_SERVICE_VERSION_CONSISTENT XPC_PROTOCOL_1_7 \
    PRODUCTION_COMPONENTS_ONLY ISOLATED_WORKTREES_CLEANED READY_FOR_SIGNING_PROMOTION; do
    [[ "${RESULT[$key]}" == "yes" ]] || pass="no"
  done
  for key in \
    UNEXPLAINED_DIFFERENCES ACCEPTANCE_SUPPORT_INCLUDED TEST_COMPONENT_INCLUDED \
    DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED RESIDUAL_PROCESS; do
    [[ "${RESULT[$key]}" == "no" ]] || pass="no"
  done
  RESULT[M12_002_RESULT]=$([[ "$pass" == "yes" ]] && print -r -- PASS || print -r -- FAIL)
  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
}

load_result_env() {
  local file="$1"
  local prefix="$2"
  [[ -f "$file" ]] || return 1
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    RESULT["${prefix}_${key}"]="$value"
  done < "$file"
}

cleanup() {
  rm -rf "$WORK_ROOT"
  if [[ ! -e "$WORK_ROOT" ]]; then
    RESULT[ISOLATED_WORKTREES_CLEANED]=yes
  fi
  local residual="no"
  for file in "$ARTIFACT_DIR/build-a/result.txt" "$ARTIFACT_DIR/build-b/result.txt"; do
    if [[ -f "$file" ]] && grep -q '^RESIDUAL_PROCESS=yes$' "$file"; then
      residual="yes"
    fi
  done
  RESULT[RESIDUAL_PROCESS]="$residual"
  write_result
}
trap cleanup EXIT

fail() {
  print -u2 "error: $*"
  write_result
  exit 1
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

clean_clone() {
  local name="$1"
  local dest="$WORK_ROOT/$name/source"
  local home="$WORK_ROOT/$name/home"
  local git_status

  mkdir -p "$WORK_ROOT/$name" "$home"
  git clone --quiet "file://$ROOT_DIR" "$dest" || return 1
  git -C "$dest" checkout --quiet --detach "$SOURCE_COMMIT" || return 1
  git_status="$(git -C "$dest" status --porcelain --untracked-files=all)"
  if [[ -z "$git_status" ]]; then
    case "$name" in
      a) RESULT[CLEAN_BUILD_A]=yes ;;
      b) RESULT[CLEAN_BUILD_B]=yes ;;
    esac
  else
    print -u2 "dirty isolated source $name before build:"
    print -u2 -- "$git_status"
    return 1
  fi

  (
    cd "$dest" || exit 1
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" \
    HERMES_RC_VERSION="$RC_VERSION" \
    SOURCE_DATE_EPOCH="$(git -C "$dest" log -1 --format=%ct)" \
    Scripts/m12_001_release_candidate_assembly.sh
  ) || return 1

  local out="$ARTIFACT_DIR/build-${name:l}"
  rm -rf "$out"
  mkdir -p "$out"
  cp -R "$dest/artifacts/m12-001/rc" "$out/rc" || return 1
  cp "$dest/artifacts/m12-001/result.txt" "$out/result.txt" || return 1
  cp "$dest/artifacts/m12-001/install-smoke.json" "$out/install-smoke.json" 2>/dev/null || true
  cp "$dest/artifacts/m12-001/uninstall-smoke.txt" "$out/uninstall-smoke.txt" 2>/dev/null || true
  case "$name" in
    a)
      RESULT[BUILD_A_RC_CREATED]=yes
      load_result_env "$out/result.txt" "BUILD_A" || return 1
      ;;
    b)
      RESULT[BUILD_B_RC_CREATED]=yes
      load_result_env "$out/result.txt" "BUILD_B" || return 1
      ;;
  esac
}

run_verifier() {
  /usr/bin/python3 - "$ROOT_DIR" "$ARTIFACT_DIR" "$RC_VERSION" "$SAFE_VERSION" "$SOURCE_COMMIT" "$SOURCE_BRANCH" <<'PY'
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
artifact_dir = Path(sys.argv[2])
rc_version = sys.argv[3]
safe_version = sys.argv[4]
source_commit = sys.argv[5]
source_branch = sys.argv[6]
build_a = artifact_dir / "build-a" / "rc"
build_b = artifact_dir / "build-b" / "rc"
staging_a = build_a / "staging"
staging_b = build_b / "staging"
result_path = artifact_dir / "verifier-result.env"
inventory_a_path = artifact_dir / "inventory-a.json"
inventory_b_path = artifact_dir / "inventory-b.json"
provenance_path = artifact_dir / "provenance.json"
differences_path = artifact_dir / "differences.json"

result = {
    "RC_VERSION_MATCH": "no",
    "SOURCE_COMMIT_MATCH": "no",
    "PAYLOAD_TOPOLOGY_MATCH": "no",
    "NORMALIZED_PAYLOAD_MATCH": "no",
    "UNEXPLAINED_DIFFERENCES": "yes",
    "INVENTORY_A_CREATED": "no",
    "INVENTORY_B_CREATED": "no",
    "INVENTORIES_MATCH": "no",
    "PROVENANCE_CREATED": "no",
    "PROVENANCE_SOURCE_RECORDED": "no",
    "PROVENANCE_OUTPUT_HASHES_RECORDED": "no",
    "MANIFEST_CONSISTENT": "no",
    "SBOM_CONSISTENT": "no",
    "CHECKSUMS_CONSISTENT": "no",
    "APP_SERVICE_VERSION_CONSISTENT": "no",
    "XPC_PROTOCOL_1_7": "no",
    "PRODUCTION_COMPONENTS_ONLY": "no",
    "ACCEPTANCE_SUPPORT_INCLUDED": "yes",
    "TEST_COMPONENT_INCLUDED": "yes",
    "DEVELOPER_PATH_EXPOSED": "yes",
    "TOKEN_EXPOSED": "yes",
    "PRIVATE_KEY_EXPOSED": "yes",
    "READY_FOR_SIGNING_PROMOTION": "no",
}
allowed_nondeterminism = [
    "release-manifest.buildTimestamp",
    "archive gzip/container timestamp and file ordering metadata",
    "Mach-O LC_UUID",
    "ad-hoc code signature blobs and CodeResources hashes",
    "temporary clean-clone build paths",
]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def rel(path, base):
    return path.relative_to(base).as_posix()

def file_type(path):
    if path.is_symlink():
        return "symlink"
    if path.is_dir():
        return "directory"
    if path.is_file():
        return "file"
    return "other"

def bundle_role(relative):
    if relative.startswith("Payload/Hermes Bridge.app/"):
        return "app"
    if relative == "Payload/Hermes Bridge.app":
        return "app"
    if relative.startswith("Payload/bin/HermesBridgeService"):
        return "service"
    if relative.startswith("Payload/bin/HermesBridgeControl"):
        return "control"
    if relative.startswith("Payload/bin/HermesBridgeServiceLifecycle"):
        return "lifecycle"
    if relative.startswith("ReleaseEvidence/"):
        return "release-evidence"
    return "support"

test_pattern = re.compile(
    r"(AcceptanceHarness|AcceptanceSupport|HermesM11003AcceptanceController|"
    r"M8001ReleaseCandidateAcceptance|M600[134].*Fixture|Tests?(/|$)|Fixtures?(/|$)|sentinel)",
    re.IGNORECASE,
)

def classification(relative):
    return "test" if test_pattern.search(relative) else "production"

def inventory(staging):
    entries = []
    for path in sorted(staging.rglob("*"), key=lambda p: rel(p, staging)):
        relative = rel(path, staging)
        st = path.lstat()
        mode = st.st_mode
        kind = file_type(path)
        digest = None
        target = None
        size = 0
        if kind == "file":
            size = st.st_size
            digest = sha256(path)
        elif kind == "symlink":
            target = os.readlink(path)
            size = len(target.encode("utf-8"))
            digest = hashlib.sha256(target.encode("utf-8")).hexdigest()
        entries.append({
            "relativePath": relative,
            "fileType": kind,
            "executable": bool(mode & stat.S_IXUSR),
            "size": size,
            "sha256": digest,
            "symlinkTarget": target,
            "bundleRole": bundle_role(relative),
            "classification": classification(relative),
        })
    return entries

def is_macho(path):
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
        return magic in {
            b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",
            b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce",
        }
    except OSError:
        return False

def normalized_plist_hash(path):
    with open(path, "rb") as f:
        obj = plistlib.load(f)
    blob = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()

def scrub_text(text):
    text = re.sub(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", "<UUID>", text)
    text = re.sub(r"/[^\s:]+/artifacts/m12-002/worktrees/[ABab]/source", "<SOURCE>", text)
    text = re.sub(r"/[^\s:]+/artifacts/m12-002/build-[ab]/rc", "<RC>", text)
    text = re.sub(r"/Users/[^\s:]+/Developer/hermes-macos-native-bridge", "<REPO>", text)
    text = re.sub(r"dataoff \d+", "dataoff <OFFSET>", text)
    text = re.sub(r"datasize \d+", "datasize <SIZE>", text)
    return text

def normalized_macho_hash(path):
    pieces = []
    for cmd in (["otool", "-l", str(path)], ["codesign", "-dv", str(path)]):
        try:
            proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
            pieces.append(scrub_text(proc.stdout))
        except FileNotFoundError:
            pieces.append(cmd[0] + " unavailable")
    try:
        proc = subprocess.run(["strings", str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
        lines = []
        for line in proc.stdout.splitlines():
            cleaned = scrub_text(line)
            if "artifacts/m12-002/worktrees" in cleaned:
                cleaned = "<SOURCE>"
            lines.append(cleaned)
        pieces.append("\n".join(sorted(set(lines))))
    except FileNotFoundError:
        pieces.append("strings unavailable")
    return hashlib.sha256("\n--\n".join(pieces).encode("utf-8", "replace")).hexdigest()

def normalized_json_hash(path, drop=()):
    obj = load_json(path)
    for key in drop:
        obj.pop(key, None)
    blob = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()

def normalized_file_hash(path):
    relative = path.as_posix()
    if relative.endswith("Info.plist"):
        return normalized_plist_hash(path)
    if relative.endswith("release-manifest.json"):
        return normalized_json_hash(path, drop=("buildTimestamp", "sourceBranch", "artifactHashes"))
    if relative.endswith("build-info.json"):
        return normalized_json_hash(path, drop=("gitStatus",))
    if "CodeSignature" in relative or relative.endswith("signing-report.env"):
        return "allowed:ad-hoc-signature"
    if is_macho(path):
        return normalized_macho_hash(path)
    return sha256(path)

def normalized_payload(staging):
    payload = {}
    for path in sorted(staging.rglob("*"), key=lambda p: rel(p, staging)):
        relative = rel(path, staging)
        if path.is_dir():
            payload[relative] = {"fileType": "directory", "hash": None, "executable": bool(path.lstat().st_mode & stat.S_IXUSR)}
        elif path.is_symlink():
            payload[relative] = {"fileType": "symlink", "hash": hashlib.sha256(os.readlink(path).encode()).hexdigest(), "executable": False}
        elif path.is_file():
            payload[relative] = {"fileType": "file", "hash": normalized_file_hash(path), "executable": bool(path.stat().st_mode & stat.S_IXUSR)}
    return payload

def production_topology(inv):
    return [
        {
            "relativePath": item["relativePath"],
            "fileType": item["fileType"],
            "executable": item["executable"],
            "bundleRole": item["bundleRole"],
            "classification": item["classification"],
        }
        for item in inv
        if item["classification"] == "production"
    ]

def manifest_paths(build):
    evidence = build / "staging" / "ReleaseEvidence"
    return {
        "manifest": evidence / "release-manifest.json",
        "sbom": evidence / "sbom.spdx.json",
        "checksums": evidence / "checksums.sha256",
        "versions": evidence / "version-manifest.json",
        "archive": build / f"HermesBridge-{safe_version}-unsigned-rc.tar.gz",
        "archive_checksum": build / f"HermesBridge-{safe_version}-unsigned-rc.tar.gz.sha256",
    }

def read_m12_result(label):
    path = artifact_dir / f"build-{label}" / "result.txt"
    data = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                data[k] = v
    return data

def checksums_valid(staging):
    checksums = staging / "ReleaseEvidence" / "checksums.sha256"
    if not checksums.exists():
        return False
    for raw in checksums.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        expected, relative = raw.split(None, 1)
        relative = relative.strip()
        path = staging / relative
        if not path.is_file() or sha256(path) != expected:
            return False
    return True

def scan_security(staging):
    findings = {"acceptance": False, "test": False, "developer_path": False, "token": False, "private_key": False}
    token_re = re.compile(rb"(token|password|credential|secret)[=:][A-Za-z0-9._/\-]{8,}|HERMES_DASHBOARD_SESSION_TOKEN=[A-Za-z0-9._/\-]{8,}")
    private_re = re.compile(rb"BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY")
    developer_re = re.compile(str(root).encode("utf-8") + rb"|/Users/[A-Za-z0-9._-]+/Developer/hermes-macos-native-bridge")
    acceptance_re = re.compile(rb"HermesBridgeAppAcceptanceHarness|HermesBridgeAppAcceptanceSupport|HermesM11003AcceptanceController|M11_003_ACCEPTANCE|m11-003-token-sentinel")
    test_re = re.compile(rb"/Tests?/|Tests?$|fixture_backend|M600[134].*Fixture|M8001ReleaseCandidateAcceptance", re.IGNORECASE)
    for path in sorted(p for p in staging.rglob("*") if p.is_file()):
        relative = rel(path, staging).encode("utf-8", "replace")
        data = b""
        try:
            data = path.read_bytes()
        except OSError:
            pass
        sample = relative + b"\n" + data
        findings["acceptance"] |= bool(acceptance_re.search(sample))
        findings["test"] |= bool(test_re.search(sample))
        findings["developer_path"] |= bool(developer_re.search(sample))
        findings["token"] |= bool(token_re.search(sample))
        findings["private_key"] |= bool(private_re.search(sample))
    return findings

def builder_versions():
    versions = {}
    for name, cmd in {
        "swift": ["swift", "--version"],
        "xcodebuild": ["xcodebuild", "-version"],
        "macos": ["sw_vers"],
        "uname": ["uname", "-a"],
    }.items():
        try:
            versions[name] = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False).stdout.strip()
        except FileNotFoundError:
            versions[name] = "unavailable"
    return versions

def plist_versions(staging):
    info = staging / "Payload" / "Hermes Bridge.app" / "Contents" / "Info.plist"
    with open(info, "rb") as f:
        plist = plistlib.load(f)
    return {
        "appShortVersion": plist.get("CFBundleShortVersionString"),
        "appBuildVersion": plist.get("CFBundleVersion"),
        "bundleIdentifier": plist.get("CFBundleIdentifier"),
        "minimumMacOSVersion": plist.get("LSMinimumSystemVersion"),
    }

inv_a = inventory(staging_a)
inv_b = inventory(staging_b)
inventory_a_path.write_text(json.dumps(inv_a, indent=2, sort_keys=True) + "\n", encoding="utf-8")
inventory_b_path.write_text(json.dumps(inv_b, indent=2, sort_keys=True) + "\n", encoding="utf-8")
result["INVENTORY_A_CREATED"] = "yes"
result["INVENTORY_B_CREATED"] = "yes"
if inv_a == inv_b:
    result["INVENTORIES_MATCH"] = "yes"

topology_a = production_topology(inv_a)
topology_b = production_topology(inv_b)
if topology_a == topology_b:
    result["PAYLOAD_TOPOLOGY_MATCH"] = "yes"

norm_a = normalized_payload(staging_a)
norm_b = normalized_payload(staging_b)
normalized_differences = []
for key in sorted(set(norm_a) | set(norm_b)):
    if norm_a.get(key) != norm_b.get(key):
        normalized_differences.append({"relativePath": key, "a": norm_a.get(key), "b": norm_b.get(key)})
if not normalized_differences:
    result["NORMALIZED_PAYLOAD_MATCH"] = "yes"
    result["UNEXPLAINED_DIFFERENCES"] = "no"

paths_a = manifest_paths(build_a)
paths_b = manifest_paths(build_b)
manifest_a = load_json(paths_a["manifest"])
manifest_b = load_json(paths_b["manifest"])
sbom_a = load_json(paths_a["sbom"])
sbom_b = load_json(paths_b["sbom"])
versions_a = load_json(paths_a["versions"])
versions_b = load_json(paths_b["versions"])
plist_a = plist_versions(staging_a)
plist_b = plist_versions(staging_b)

archive_name = f"HermesBridge-{safe_version}-unsigned-rc.tar.gz"
version_fields = [
    manifest_a.get("rcVersion"), manifest_b.get("rcVersion"),
    versions_a.get("version"), versions_b.get("version"),
    plist_a.get("appShortVersion"), plist_b.get("appShortVersion"),
    plist_a.get("appBuildVersion"), plist_b.get("appBuildVersion"),
]
component_versions = list((manifest_a.get("componentVersions") or {}).values()) + list((manifest_b.get("componentVersions") or {}).values())
component_versions += [c.get("version") for c in (versions_a.get("components") or {}).values()]
component_versions += [c.get("version") for c in (versions_b.get("components") or {}).values()]
sbom_versions = [p.get("versionInfo") for p in sbom_a.get("packages", []) if p.get("name") in {"Hermes Bridge.app", "HermesBridgeService", "HermesBridgeControl"}]
sbom_versions += [p.get("versionInfo") for p in sbom_b.get("packages", []) if p.get("name") in {"Hermes Bridge.app", "HermesBridgeService", "HermesBridgeControl"}]
filename_match = paths_a["archive"].name == archive_name and paths_b["archive"].name == archive_name
if filename_match and all(v == rc_version for v in version_fields + component_versions + sbom_versions):
    result["RC_VERSION_MATCH"] = "yes"
    result["APP_SERVICE_VERSION_CONSISTENT"] = "yes"

if manifest_a.get("sourceCommit") == source_commit and manifest_b.get("sourceCommit") == source_commit:
    result["SOURCE_COMMIT_MATCH"] = "yes"

manifest_stable_a = dict(manifest_a)
manifest_stable_b = dict(manifest_b)
for key in ("buildTimestamp", "sourceBranch", "artifactHashes"):
    manifest_stable_a.pop(key, None)
    manifest_stable_b.pop(key, None)
if (
    manifest_stable_a == manifest_stable_b
    and manifest_a.get("rcVersion") == rc_version
    and manifest_a.get("xpcProtocolVersion") == "1.7"
    and manifest_b.get("xpcProtocolVersion") == "1.7"
):
    result["MANIFEST_CONSISTENT"] = "yes"
    result["XPC_PROTOCOL_1_7"] = "yes"

def sbom_inventory(sbom):
    return sorted(
        (p.get("SPDXID"), p.get("name"), p.get("versionInfo"), p.get("licenseDeclared"), p.get("licenseConcluded"))
        for p in sbom.get("packages", [])
    )
if sbom_inventory(sbom_a) == sbom_inventory(sbom_b) and all(v == rc_version for v in sbom_versions):
    result["SBOM_CONSISTENT"] = "yes"

if checksums_valid(staging_a) and checksums_valid(staging_b):
    result["CHECKSUMS_CONSISTENT"] = "yes"

sec_a = scan_security(staging_a)
sec_b = scan_security(staging_b)
if not sec_a["acceptance"] and not sec_b["acceptance"]:
    result["ACCEPTANCE_SUPPORT_INCLUDED"] = "no"
if not sec_a["test"] and not sec_b["test"] and not any(i["classification"] == "test" for i in inv_a + inv_b):
    result["TEST_COMPONENT_INCLUDED"] = "no"
if result["ACCEPTANCE_SUPPORT_INCLUDED"] == "no" and result["TEST_COMPONENT_INCLUDED"] == "no":
    result["PRODUCTION_COMPONENTS_ONLY"] = "yes"
if not sec_a["developer_path"] and not sec_b["developer_path"]:
    result["DEVELOPER_PATH_EXPOSED"] = "no"
if not sec_a["token"] and not sec_b["token"]:
    result["TOKEN_EXPOSED"] = "no"
if not sec_a["private_key"] and not sec_b["private_key"]:
    result["PRIVATE_KEY_EXPOSED"] = "no"

output_artifacts = []
for label, build, inv in (("A", build_a, inv_a), ("B", build_b, inv_b)):
    for path in [
        build / archive_name,
        build / f"{archive_name}.sha256",
        build / "staging" / "ReleaseEvidence" / "release-manifest.json",
        build / "staging" / "ReleaseEvidence" / "sbom.spdx.json",
        build / "staging" / "ReleaseEvidence" / "checksums.sha256",
    ]:
        if path.exists():
            output_artifacts.append({
                "build": label,
                "name": path.name,
                "path": path.relative_to(artifact_dir).as_posix(),
                "sha256": sha256(path),
            })
    output_artifacts.append({
        "build": label,
        "name": f"inventory-{label.lower()}.json",
        "path": f"inventory-{label.lower()}.json",
        "sha256": sha256(artifact_dir / f"inventory-{label.lower()}.json"),
    })

if output_artifacts and all(item.get("sha256") for item in output_artifacts):
    result["PROVENANCE_OUTPUT_HASHES_RECORDED"] = "yes"
if source_commit:
    result["PROVENANCE_SOURCE_RECORDED"] = "yes"

exact_differences = []
sha_by_path_a = {item["relativePath"]: item["sha256"] for item in inv_a if item["fileType"] == "file"}
sha_by_path_b = {item["relativePath"]: item["sha256"] for item in inv_b if item["fileType"] == "file"}
for key in sorted(set(sha_by_path_a) | set(sha_by_path_b)):
    if sha_by_path_a.get(key) != sha_by_path_b.get(key):
        exact_differences.append({"relativePath": key, "a": sha_by_path_a.get(key), "b": sha_by_path_b.get(key)})

differences = {
    "exactDifferences": exact_differences,
    "normalizedDifferences": normalized_differences,
    "allowedNondeterminism": allowed_nondeterminism,
}
differences_path.write_text(json.dumps(differences, indent=2, sort_keys=True) + "\n", encoding="utf-8")

provenance = {
    "_type": "https://in-toto.io/Statement/v1",
    "predicateType": "https://slsa.dev/provenance/v1-inspired-unofficial",
    "subject": output_artifacts,
    "predicate": {
        "product": "Hermes Bridge",
        "rcVersion": rc_version,
        "source": {
            "repository": str(root),
            "commit": source_commit,
            "branchInformational": source_branch,
        },
        "buildDefinition": {
            "buildCommand": "HERMES_RC_VERSION=<version> Scripts/m12_001_release_candidate_assembly.sh",
            "externalParameters": {"rcVersion": rc_version, "sourceCommit": source_commit},
            "internalParameters": {"isolatedHome": True, "permanentInstall": False},
            "resolvedDependencies": [
                {"uri": f"git+file://{root}", "digest": {"gitCommit": source_commit}},
                {"uri": "Scripts/m12_001_release_candidate_assembly.sh", "digest": {"sha256": sha256(root / "Scripts" / "m12_001_release_candidate_assembly.sh")}},
            ],
        },
        "runDetails": {
            "builder": {"id": "local-macos-clean-clone", "version": builder_versions()},
            "metadata": {
                "targetArchitecture": manifest_a.get("targetArchitecture"),
                "minimumMacOSVersion": manifest_a.get("minimumMacOSVersion"),
                "xpcProtocolVersion": manifest_a.get("xpcProtocolVersion"),
                "signingState": manifest_a.get("signingState"),
                "notarizationState": manifest_a.get("notarizationState"),
            },
            "byproducts": [
                {"name": "payloadInventoryA", "path": "inventory-a.json"},
                {"name": "payloadInventoryB", "path": "inventory-b.json"},
                {"name": "comparison", "path": "differences.json"},
            ],
        },
        "reproducibility": {
            "sourceCommitFixed": True,
            "payloadTopologyMatch": result["PAYLOAD_TOPOLOGY_MATCH"] == "yes",
            "normalizedPayloadMatch": result["NORMALIZED_PAYLOAD_MATCH"] == "yes",
            "unexplainedDifferences": normalized_differences,
            "allowedNondeterministicFields": allowed_nondeterminism,
            "exactDifferences": exact_differences,
        },
        "sourceCleanliness": {
            "committed": True,
            "identicalInBothCleanClones": result["SOURCE_COMMIT_MATCH"] == "yes",
            "untrackedFilesAffectingBuild": False,
            "localSourceModifications": False,
        },
        "security": {
            "productionComponentsOnly": result["PRODUCTION_COMPONENTS_ONLY"] == "yes",
            "acceptanceSupportIncluded": result["ACCEPTANCE_SUPPORT_INCLUDED"] == "yes",
            "testComponentIncluded": result["TEST_COMPONENT_INCLUDED"] == "yes",
            "developerPathExposed": result["DEVELOPER_PATH_EXPOSED"] == "yes",
            "tokenExposed": result["TOKEN_EXPOSED"] == "yes",
            "privateKeyExposed": result["PRIVATE_KEY_EXPOSED"] == "yes",
        },
    },
}
provenance_path.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8")
result["PROVENANCE_CREATED"] = "yes"

promotion_keys = [
    "RC_VERSION_MATCH", "SOURCE_COMMIT_MATCH", "PAYLOAD_TOPOLOGY_MATCH",
    "NORMALIZED_PAYLOAD_MATCH", "INVENTORIES_MATCH", "PROVENANCE_CREATED",
    "PROVENANCE_SOURCE_RECORDED", "PROVENANCE_OUTPUT_HASHES_RECORDED",
    "MANIFEST_CONSISTENT", "SBOM_CONSISTENT", "CHECKSUMS_CONSISTENT",
    "APP_SERVICE_VERSION_CONSISTENT", "XPC_PROTOCOL_1_7", "PRODUCTION_COMPONENTS_ONLY",
]
security_safe = (
    result["UNEXPLAINED_DIFFERENCES"] == "no"
    and result["ACCEPTANCE_SUPPORT_INCLUDED"] == "no"
    and result["TEST_COMPONENT_INCLUDED"] == "no"
    and result["DEVELOPER_PATH_EXPOSED"] == "no"
    and result["TOKEN_EXPOSED"] == "no"
    and result["PRIVATE_KEY_EXPOSED"] == "no"
)
if all(result[k] == "yes" for k in promotion_keys) and security_safe:
    result["READY_FOR_SIGNING_PROMOTION"] = "yes"

with open(result_path, "w", encoding="utf-8") as f:
    for key in sorted(result):
        f.write(f"{key}={result[key]}\n")
PY
}

merge_verifier_results() {
  local file="$ARTIFACT_DIR/verifier-result.env"
  [[ -f "$file" ]] || return 1
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    RESULT[$key]="$value"
  done < "$file"
}

set_default_results
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
write_result

[[ -d "$ROOT_DIR/.git" ]] || fail "unexpected repository root"
if [[ -z "$SOURCE_COMMIT" ]]; then
  SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi
[[ -n "$SOURCE_COMMIT" ]] || fail "could not determine source commit"
git -C "$ROOT_DIR" cat-file -e "$SOURCE_COMMIT^{commit}" 2>/dev/null || fail "source commit does not exist: $SOURCE_COMMIT"
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse "$SOURCE_COMMIT^{commit}")"
RESULT[SOURCE_COMMIT_FIXED]=yes

clean_clone "a" || fail "RC A clean rebuild failed"
clean_clone "b" || fail "RC B clean rebuild failed"
run_verifier || fail "reproducibility/provenance verification failed"
merge_verifier_results || fail "could not read verifier result"
write_result
exit 0
