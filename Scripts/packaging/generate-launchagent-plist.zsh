#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  print -u2 "usage: generate-launchagent-plist.zsh <output-plist> <service-binary>"
  exit 64
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
output_path="$1"
service_binary="$2"
template_path="$repo_root/Packaging/LaunchAgent/com.hermes.bridge.plist.template"

if [[ "$output_path" != /* || "$service_binary" != /* ]]; then
  print -u2 "output and service binary paths must be absolute"
  exit 65
fi

output_parent="$(dirname "$output_path")"
if [[ ! -d "$output_parent" ]]; then
  print -u2 "output parent does not exist"
  exit 66
fi

output_parent_real="$(cd "$output_parent" && pwd -P)"
artifact_root="$repo_root/artifacts/m2-008"
if [[ "$output_parent_real" != "$artifact_root" && "$output_parent_real" != "$artifact_root"/* ]]; then
  print -u2 "refusing to write outside artifacts/m2-008"
  exit 67
fi

if [[ ! -f "$service_binary" || ! -x "$service_binary" ]]; then
  print -u2 "service binary is missing or not executable"
  exit 68
fi

service_binary_real="$(cd "$(dirname "$service_binary")" && pwd -P)/$(basename "$service_binary")"
logs_dir="$output_parent_real/logs"
mkdir -p "$logs_dir"
chmod 700 "$logs_dir"

tmp_path="$output_path.tmp.$$"
sed \
  -e "s#__HERMES_BRIDGE_SERVICE_BINARY__#$service_binary_real#g" \
  -e "s#__HERMES_BRIDGE_LOGS_DIR__#$logs_dir#g" \
  "$template_path" > "$tmp_path"

plutil -lint "$tmp_path" >/dev/null
mv "$tmp_path" "$output_path"
plutil -lint "$output_path" >/dev/null
print "generated=$output_path"
