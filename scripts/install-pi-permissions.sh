#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION='0.2.0'

apply=false
target_home=${HOME:-}

usage() {
  cat <<'EOF'
Usage: install-pi-permissions.sh [options]

Install and verify the factory's reproducible Pi permission runtime and global
policy. The frozen npm installation requires network access; inspection does
not.

Options:
  --target-home PATH
                    User home to install beneath (default: current HOME)
  --apply           Perform approved writes; otherwise inspect only
  -h, --help        Show this help
  --version         Show the script version

The script never replaces a differing runtime or policy. It preserves existing
Pi settings and packages, and registers the extension only after the frozen
runtime and policy have been verified.
EOF
}

fail() {
  printf 'install-pi-permissions: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'install-pi-permissions: %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --target-home)
      [[ $# -ge 2 ]] || fail '--target-home requires a value'
      target_home=$2
      shift 2
      ;;
    --apply)
      apply=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      printf 'install-pi-permissions %s\n' "$SCRIPT_VERSION"
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$target_home" ]] || fail 'HOME is empty; pass --target-home'
[[ "$target_home" == /* ]] || fail '--target-home must be an absolute path'
[[ -d "$target_home" ]] || fail "target home not found: $target_home"

require_command awk
require_command chmod
require_command cmp
require_command dirname
require_command install
require_command jq
require_command mkdir
require_command mktemp
require_command mv
require_command node
require_command npm
require_command pi
require_command rm
require_command stat

node_major=$(node -p 'Number(process.versions.node.split(".")[0])') ||
  fail 'could not determine the Node.js version'
[[ "$node_major" -ge 22 ]] || fail 'Node.js 22 or newer is required by the pinned Pi extension'

if command -v sha256sum >/dev/null 2>&1; then
  hash_command='sha256sum'
elif command -v shasum >/dev/null 2>&1; then
  hash_command='shasum'
else
  fail 'required command not found: sha256sum or shasum'
fi

hash_file() {
  if [[ "$hash_command" == 'sha256sum' ]]; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

script_directory=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
factory_root=$(CDPATH='' cd -- "$script_directory/.." && pwd -P)
readonly script_directory factory_root
readonly lock_file="$factory_root/pi-permissions.lock"

[[ -f "$lock_file" && ! -L "$lock_file" ]] ||
  fail "permission lock not found: $lock_file"

jq -e '
  .schemaVersion == 2 and
  (.extension.name | type == "string") and
  (.extension.version | type == "string") and
  (.runtime.packageDefinition | type == "string") and
  (.runtime.packageDefinitionSha256 | test("^[0-9a-f]{64}$")) and
  (.runtime.packageLock | type == "string") and
  (.runtime.packageLockSha256 | test("^[0-9a-f]{64}$")) and
  (.runtime.extensionPath | type == "string") and
  (.policy.source | type == "string") and
  (.policy.sha256 | test("^[0-9a-f]{64}$"))
' "$lock_file" >/dev/null || fail 'pi-permissions.lock has an unsupported schema'

extension_name=$(jq -er '.extension.name' "$lock_file")
extension_version=$(jq -er '.extension.version' "$lock_file")
package_definition_relative=$(jq -er '.runtime.packageDefinition' "$lock_file")
expected_package_definition_hash=$(jq -er '.runtime.packageDefinitionSha256' "$lock_file")
package_lock_relative=$(jq -er '.runtime.packageLock' "$lock_file")
expected_package_lock_hash=$(jq -er '.runtime.packageLockSha256' "$lock_file")
extension_relative=$(jq -er '.runtime.extensionPath' "$lock_file")
source_config_relative=$(jq -er '.policy.source' "$lock_file")
expected_config_hash=$(jq -er '.policy.sha256' "$lock_file")

[[ "$extension_name" == '@gotgenes/pi-permission-system' ]] ||
  fail "unexpected extension in lock: $extension_name"
[[ "$package_definition_relative" == 'pi-extension-runtime/package.json' &&
  "$package_lock_relative" == 'pi-extension-runtime/package-lock.json' &&
  "$extension_relative" == 'node_modules/@gotgenes/pi-permission-system' &&
  "$source_config_relative" == 'config/pi-permission-system.json' ]] ||
  fail 'pi-permissions.lock contains an unsafe factory path'

source_package_definition="$factory_root/$package_definition_relative"
source_package_lock="$factory_root/$package_lock_relative"
source_config="$factory_root/$source_config_relative"
readonly extension_name extension_version source_package_definition source_package_lock source_config

for source_file in "$source_package_definition" "$source_package_lock" "$source_config"; do
  [[ -f "$source_file" && ! -L "$source_file" ]] || fail "locked source file is missing or unsafe: $source_file"
done

[[ "$(hash_file "$source_package_definition")" == "$expected_package_definition_hash" ]] ||
  fail 'runtime package definition does not match pi-permissions.lock'
[[ "$(hash_file "$source_package_lock")" == "$expected_package_lock_hash" ]] ||
  fail 'runtime package lock does not match pi-permissions.lock'
[[ "$(hash_file "$source_config")" == "$expected_config_hash" ]] ||
  fail 'source permission configuration does not match pi-permissions.lock'

jq -e --arg extension "$extension_name" --arg version "$extension_version" '
  .private == true and .dependencies[$extension] == $version
' "$source_package_definition" >/dev/null || fail 'runtime package definition does not pin the extension'
jq -e --arg extension "$extension_name" --arg version "$extension_version" '
  .lockfileVersion == 3 and
  .packages[""].dependencies[$extension] == $version and
  .packages[("node_modules/" + $extension)].version == $version and
  ([.packages | to_entries[] | select(.key != "") |
    (.key | test("^node_modules/(@[A-Za-z0-9._-]+/)?[A-Za-z0-9._-]+$")) and
    (.value.version | type == "string" and length > 0) and
    (.value.resolved | type == "string" and startswith("https://registry.npmjs.org/")) and
    (.value.integrity | type == "string" and startswith("sha512-"))] | all)
' "$source_package_lock" >/dev/null || fail 'runtime package lock is incomplete or inconsistent'
jq empty "$source_config" || fail 'source permission configuration is not valid JSON'

agent_directory="$target_home/.pi/agent"
runtime_parent="$agent_directory/software-factory"
runtime_directory="$runtime_parent/pi-permission-runtime"
installed_extension="$runtime_directory/$extension_relative"
settings_file="$agent_directory/settings.json"
config_directory="$agent_directory/extensions/pi-permission-system"
installed_config="$config_directory/config.json"
registered_path="software-factory/pi-permission-runtime/$extension_relative"
readonly agent_directory runtime_parent runtime_directory installed_extension settings_file
readonly config_directory installed_config registered_path

settings_existed=false
settings_hash_before=''
if [[ -e "$settings_file" || -L "$settings_file" ]]; then
  [[ -f "$settings_file" ]] || fail "existing Pi settings are not a readable file: $settings_file"
  jq -e '
    type == "object" and
    ((.packages // []) | type == "array") and
    all(.packages[]?;
      type == "string" or
      (type == "object" and (.source | type == "string")))
  ' "$settings_file" >/dev/null || fail "existing Pi settings are invalid: $settings_file"
  settings_existed=true
  settings_hash_before=$(hash_file "$settings_file")
fi

registered_count=0
legacy_registration_count=0
if $settings_existed; then
  registered_count=$(jq -r --arg expected "$registered_path" '
    [.packages[]? | (if type == "string" then . else .source end) | select(. == $expected)] | length
  ' "$settings_file")
  legacy_registration_count=$(jq -r --arg prefix "npm:$extension_name@" '
    [.packages[]? | (if type == "string" then . else .source end) | select(startswith($prefix))] | length
  ' "$settings_file")
fi
[[ "$registered_count" -le 1 ]] || fail 'Pi settings register the factory runtime more than once'
[[ "$legacy_registration_count" -eq 0 ]] ||
  fail "Pi settings still contain the legacy floating registration; remove npm:$extension_name only after backing up settings"

verify_runtime() {
  local candidate=$1
  local lock_key expected_version package_directory package_manifest

  [[ -d "$candidate" && ! -L "$candidate" ]] || fail "permission runtime is missing or unsafe: $candidate"
  [[ -f "$candidate/package.json" && ! -L "$candidate/package.json" ]] ||
    fail "installed runtime package definition is missing: $candidate"
  [[ -f "$candidate/package-lock.json" && ! -L "$candidate/package-lock.json" ]] ||
    fail "installed runtime package lock is missing: $candidate"
  cmp -s "$source_package_definition" "$candidate/package.json" ||
    fail 'installed runtime package definition differs from factory source'
  cmp -s "$source_package_lock" "$candidate/package-lock.json" ||
    fail 'installed runtime package lock differs from factory source'

  while IFS=$'\t' read -r lock_key expected_version; do
    package_directory="$candidate/$lock_key"
    package_manifest="$package_directory/package.json"
    [[ -f "$package_manifest" && ! -L "$package_manifest" ]] ||
      fail "locked package is missing: ${lock_key#node_modules/}"
    jq -e --arg version "$expected_version" '.version == $version' "$package_manifest" >/dev/null ||
      fail "installed package version differs from lock: ${lock_key#node_modules/}"
  done < <(jq -er '.packages | to_entries[] | select(.key != "") |
    [.key, .value.version] | @tsv' "$source_package_lock")

  (
    cd "$candidate"
    node -e "const parser = require('tree-sitter-bash'); if (!parser || !parser.language) process.exit(1)"
  ) || fail 'tree-sitter-bash cannot load; Bash permission parsing is unavailable'
}

runtime_missing=false
if [[ -e "$runtime_directory" || -L "$runtime_directory" ]]; then
  verify_runtime "$runtime_directory"
else
  runtime_missing=true
fi

config_missing=false
config_mode_change=false
if [[ -e "$installed_config" || -L "$installed_config" ]]; then
  [[ -f "$installed_config" && ! -L "$installed_config" ]] ||
    fail "existing permission config is not a regular file: $installed_config"
  cmp -s "$source_config" "$installed_config" ||
    fail "existing permission config differs from factory policy: $installed_config"
  if config_mode=$(stat -f '%Lp' "$installed_config" 2>/dev/null); then
    :
  else
    config_mode=$(stat -c '%a' "$installed_config")
  fi
  [[ "$config_mode" == '600' ]] || config_mode_change=true
else
  config_missing=true
fi

info "version=$SCRIPT_VERSION"
info "mode=$(if $apply; then printf apply; else printf inspect; fi)"
info "target_home=$target_home"
info "extension=$extension_name@$extension_version"
info "runtime_lock_sha256=$expected_package_lock_hash"

if $runtime_missing; then
  info "PLAN frozen npm install into dedicated runtime: $runtime_directory"
else
  info 'dedicated permission runtime verified'
fi
if [[ "$registered_count" -eq 0 ]]; then
  info "PLAN register verified local extension with Pi: $registered_path"
else
  info 'local Pi extension registration verified'
fi
if $config_missing; then
  info "PLAN install global policy: $installed_config"
elif $config_mode_change; then
  info "PLAN secure global policy permissions: $installed_config"
else
  info 'global policy verified'
fi

if ! $apply; then
  if $runtime_missing || [[ "$registered_count" -eq 0 ]] || $config_missing || $config_mode_change; then
    exit 2
  fi
  info 'pinned Pi permission extension and policy verified'
  exit 0
fi

active_stage=''
cleanup() {
  if [[ -n "$active_stage" && "$active_stage" == "$runtime_parent/.pi-permission-runtime.stage."* &&
    -d "$active_stage" ]]; then
    rm -rf -- "$active_stage"
  fi
}
trap cleanup EXIT

if $runtime_missing; then
  mkdir -p "$runtime_parent"
  active_stage=$(mktemp -d "$runtime_parent/.pi-permission-runtime.stage.XXXXXX")
  install -m 644 "$source_package_definition" "$active_stage/package.json"
  install -m 644 "$source_package_lock" "$active_stage/package-lock.json"
  if ! (
    cd "$active_stage"
    npm ci --ignore-scripts --legacy-peer-deps --omit=dev --no-audit --no-fund
  ); then
    fail 'frozen npm installation failed; active Pi settings were not changed'
  fi
  verify_runtime "$active_stage"
  [[ ! -e "$runtime_directory" && ! -L "$runtime_directory" ]] ||
    fail "permission runtime appeared during installation: $runtime_directory"
  mv "$active_stage" "$runtime_directory"
  active_stage=''
  info 'frozen permission runtime installed and verified'
fi

if $config_missing; then
  mkdir -p "$config_directory"
  config_stage=$(mktemp "$config_directory/.config.json.XXXXXX")
  install -m 600 "$source_config" "$config_stage"
  [[ ! -e "$installed_config" && ! -L "$installed_config" ]] || {
    rm -f -- "$config_stage"
    fail "permission config appeared during installation: $installed_config"
  }
  mv "$config_stage" "$installed_config"
  info 'global policy installed'
elif $config_mode_change; then
  chmod 600 "$installed_config"
  info 'global policy permissions secured'
fi

if [[ "$registered_count" -eq 0 ]]; then
  if $settings_existed; then
    [[ -f "$settings_file" && "$(hash_file "$settings_file")" == "$settings_hash_before" ]] ||
      fail 'Pi settings changed during installation; local extension was not registered'
  else
    [[ ! -e "$settings_file" && ! -L "$settings_file" ]] ||
      fail 'Pi settings appeared during installation; local extension was not registered'
  fi
  PI_CODING_AGENT_DIR="$agent_directory" pi install "$installed_extension" ||
    fail 'Pi activation failed; the verified runtime and policy were retained for a safe retry'
  info 'verified local extension registered with Pi'
fi

verify_runtime "$runtime_directory"
[[ -f "$settings_file" ]] || fail 'Pi settings are missing after activation'
jq -e --arg expected "$registered_path" '
  [.packages[]? | (if type == "string" then . else .source end) | select(. == $expected)] | length == 1
' "$settings_file" >/dev/null || fail 'Pi did not retain the exact local extension registration'
cmp -s "$source_config" "$installed_config" || fail 'installed permission config failed final verification'
if installed_mode=$(stat -f '%Lp' "$installed_config" 2>/dev/null); then
  :
else
  installed_mode=$(stat -c '%a' "$installed_config")
fi
[[ "$installed_mode" == '600' ]] || fail 'installed permission config is not mode 600'

info 'pinned Pi permission extension and policy installed and verified'
