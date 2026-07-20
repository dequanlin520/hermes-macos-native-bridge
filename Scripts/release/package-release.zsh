#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: package-release.zsh --staging-root <root> --version <version> --mode <adhoc|developer-id>"
}

die() {
  print -u2 "error: $*"
  exit 1
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
staging_root=""
version=""
mode=""

while (( $# > 0 )); do
  case "$1" in
    --staging-root)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      staging_root="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      version="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      mode="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "unknown argument: $1"
      usage
      exit 64
      ;;
  esac
done

[[ -n "$staging_root" && -n "$version" && -n "$mode" ]] || { usage; exit 64; }
[[ "$staging_root" == /* ]] || staging_root="$PWD/$staging_root"
staging_root="$(cd "$staging_root" && pwd -P)"
[[ "$staging_root" == "$repo_root/artifacts/"* ]] || die "staging root must be artifact-owned"

evidence_root="$staging_root/ReleaseEvidence"
mkdir -p "$evidence_root"

sbom="$evidence_root/sbom.spdx.json"
checksums="$evidence_root/checksums.sha256"
deterministic_list="$evidence_root/staging-files.txt"

(
  cd "$staging_root"
  find Payload ReleaseEvidence -type f \
    ! -path 'ReleaseEvidence/checksums.sha256' \
    ! -path 'ReleaseEvidence/staging-files.txt' \
    ! -path 'ReleaseEvidence/sbom.spdx.json' \
    ! -name '*.log' \
    | LC_ALL=C sort > "$deterministic_list"
)

(
  cd "$staging_root"
  while IFS= read -r item; do
    shasum -a 256 "$item"
  done < "$deterministic_list" > "$checksums"
)

package_lines_file="$(mktemp -t hermes-sbom-files.XXXXXX)"
trap 'rm -f "$package_lines_file"' EXIT
first_file="yes"
while IFS= read -r item; do
  [[ -n "$item" ]] || continue
  checksum="$(cd "$staging_root" && shasum -a 256 "$item" | awk '{print $1}')"
  spdx_id="$(printf '%s' "$item" | tr -c 'A-Za-z0-9' '-')"
  if [[ "$first_file" == "yes" ]]; then
    first_file="no"
  else
    printf ',\n' >> "$package_lines_file"
  fi
  printf '    {"SPDXID":"SPDXRef-File-%s","fileName":"%s","checksums":[{"algorithm":"SHA256","checksumValue":"%s"}]}' "$spdx_id" "$item" "$checksum" >> "$package_lines_file"
done < "$deterministic_list"

cat > "$sbom" <<EOF
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "HermesMacOSNativeBridge-$version",
  "documentNamespace": "https://github.com/dequanlin520/hermes-macos-native-bridge/spdx/$version/$(git rev-parse --short HEAD)",
  "creationInfo": {
    "created": "$(date -u -r "${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}" '+%Y-%m-%dT%H:%M:%SZ')",
    "creators": ["Tool: Scripts/release/package-release.zsh"]
  },
  "files": [
$(cat "$package_lines_file")
  ]
}
EOF

(
  cd "$staging_root"
  shasum -a 256 "ReleaseEvidence/sbom.spdx.json" >> "$checksums"
)

archive_suffix="unsigned-rc"
if [[ "$mode" == "developer-id" ]]; then
  archive_suffix="developer-id"
fi
archive="$staging_root:h/HermesBridge-$version-$archive_suffix.tar.gz"
rm -f "$archive"

find "$staging_root" -exec touch -h -t 198001010000 {} +
(
  cd "$staging_root:h"
  COPYFILE_DISABLE=1 tar -czf "$archive" --format ustar -C "$staging_root" -T "$deterministic_list" >/dev/null 2>&1 || {
    tar -czf "$archive" -C "$staging_root" Payload ReleaseEvidence
  }
)

(
  cd "$archive:h"
  shasum -a 256 "$archive:t" > "$archive:t.sha256"
)
print "archive=$archive"
