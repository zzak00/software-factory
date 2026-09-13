#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
install_script="$project_root/scripts/install-pi-permissions.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/install-pi-permissions-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  expected=$1
  actual=$2
  context=$3
  [[ "$actual" -eq "$expected" ]] ||
    fail "$context returned $actual, expected $expected"
}

fake_bin="$test_root/bin"
fake_log="$test_root/pi-calls"
mkdir -p "$fake_bin"
ln -s "$project_root/test/fakes/pi-permissions-pi" "$fake_bin/pi"
ln -s "$project_root/test/fakes/pi-permissions-npm" "$fake_bin/npm"
export PATH="$fake_bin:$PATH"
export PI_PERMISSIONS_FAKE_LOG="$fake_log"

fresh_home="$test_root/fresh-home"
mkdir -p "$fresh_home"
mkdir -p "$fresh_home/.pi/agent"
printf '%s\n' '{"packages":["npm:other-extension@1.0.0"],"theme":"keep-me"}' \
  >"$fresh_home/.pi/agent/settings.json"
cp "$fresh_home/.pi/agent/settings.json" "$test_root/settings-before-inspect"

set +e
"$install_script" --target-home "$fresh_home" >"$test_root/inspect-output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'fresh inspect'
cmp -s "$test_root/settings-before-inspect" "$fresh_home/.pi/agent/settings.json" ||
  fail 'inspect mode changed Pi settings'
[[ ! -e "$fresh_home/.pi/agent/software-factory" ]] ||
  fail 'inspect mode created a Pi runtime'
grep -Fq 'PLAN frozen npm install into dedicated runtime' "$test_root/inspect-output" ||
  fail 'fresh inspect omitted the frozen runtime plan'
grep -Fq 'PLAN register verified local extension with Pi' "$test_root/inspect-output" ||
  fail 'fresh inspect omitted the local activation plan'
grep -Fq 'PLAN install global policy' "$test_root/inspect-output" ||
  fail 'fresh inspect omitted the policy plan'

"$install_script" --target-home "$fresh_home" --apply \
  >"$test_root/apply-output" 2>&1
grep -Fqx 'npm ci --ignore-scripts --legacy-peer-deps --omit=dev --no-audit --no-fund' \
  "$fake_log" || fail 'apply did not use the frozen npm installation command'
grep -Fq 'pi install ' "$fake_log" || fail 'apply did not register the local extension with Pi'
runtime_directory="$fresh_home/.pi/agent/software-factory/pi-permission-runtime"
cmp -s "$project_root/pi-extension-runtime/package-lock.json" \
  "$runtime_directory/package-lock.json" || fail 'installed runtime lock differs from factory lock'
jq -e '
  .theme == "keep-me" and
  (.packages | index("npm:other-extension@1.0.0")) != null and
  (.packages | index("software-factory/pi-permission-runtime/node_modules/@gotgenes/pi-permission-system")) != null
' "$fresh_home/.pi/agent/settings.json" >/dev/null ||
  fail 'activation did not preserve existing Pi settings and packages'
cmp -s "$project_root/config/pi-permission-system.json" \
  "$fresh_home/.pi/agent/extensions/pi-permission-system/config.json" ||
  fail 'apply did not install the exact global policy'

if installed_mode=$(stat -f '%Lp' \
  "$fresh_home/.pi/agent/extensions/pi-permission-system/config.json" 2>/dev/null); then
  :
else
  installed_mode=$(stat -c '%a' \
    "$fresh_home/.pi/agent/extensions/pi-permission-system/config.json")
fi
[[ "$installed_mode" == '600' ]] || fail 'installed policy is not mode 600'

"$install_script" --target-home "$fresh_home" \
  >"$test_root/idempotent-output" 2>&1
grep -Fq 'pinned Pi permission extension and policy verified' \
  "$test_root/idempotent-output" ||
  fail 'idempotent inspect did not verify the installation'

conflict_home="$test_root/conflict-home"
conflict_config="$conflict_home/.pi/agent/extensions/pi-permission-system/config.json"
mkdir -p "$(dirname -- "$conflict_config")"
printf '%s\n' '{"local":"policy"}' >"$conflict_config"

set +e
"$install_script" --target-home "$conflict_home" --apply \
  >"$test_root/conflict-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'conflicting apply'
grep -Fqx '{"local":"policy"}' "$conflict_config" ||
  fail 'conflicting policy was overwritten'
[[ ! -e "$conflict_home/.pi/agent/npm" ]] ||
  fail 'installer added the package after finding a policy conflict'

failed_home="$test_root/failed-home"
mkdir -p "$failed_home/.pi/agent"
printf '%s\n' '{"packages":["npm:other-extension@1.0.0"],"theme":"unchanged"}' \
  >"$failed_home/.pi/agent/settings.json"
cp "$failed_home/.pi/agent/settings.json" "$test_root/settings-before-failure"
export PI_PERMISSIONS_FAKE_NPM_FAIL=true
set +e
"$install_script" --target-home "$failed_home" --apply \
  >"$test_root/npm-failure-output" 2>&1
command_status=$?
set -e
unset PI_PERMISSIONS_FAKE_NPM_FAIL
assert_status 1 "$command_status" 'failed frozen install'
cmp -s "$test_root/settings-before-failure" "$failed_home/.pi/agent/settings.json" ||
  fail 'failed frozen install changed active Pi settings'
[[ ! -e "$failed_home/.pi/agent/software-factory/pi-permission-runtime" ]] ||
  fail 'failed frozen install activated an incomplete runtime'

interrupted_home="$test_root/interrupted-home"
mkdir -p "$interrupted_home/.pi/agent"
printf '%s\n' '{"packages":[],"theme":"survives"}' \
  >"$interrupted_home/.pi/agent/settings.json"
export PI_PERMISSIONS_FAKE_PI_FAIL=true
set +e
"$install_script" --target-home "$interrupted_home" --apply \
  >"$test_root/activation-failure-output" 2>&1
command_status=$?
set -e
unset PI_PERMISSIONS_FAKE_PI_FAIL
assert_status 1 "$command_status" 'interrupted activation'
jq -e '.packages == [] and .theme == "survives"' \
  "$interrupted_home/.pi/agent/settings.json" >/dev/null ||
  fail 'interrupted activation changed existing Pi settings'
[[ -d "$interrupted_home/.pi/agent/software-factory/pi-permission-runtime" ]] ||
  fail 'verified runtime was not retained for activation recovery'
"$install_script" --target-home "$interrupted_home" --apply \
  >"$test_root/activation-recovery-output" 2>&1

second_home="$test_root/second-home"
mkdir -p "$second_home"
"$install_script" --target-home "$second_home" --apply \
  >"$test_root/second-install-output" 2>&1
cmp -s "$runtime_directory/package-lock.json" \
  "$second_home/.pi/agent/software-factory/pi-permission-runtime/package-lock.json" ||
  fail 'repeated fresh installations did not use the same dependency graph'

drift_home="$test_root/drift-home"
mkdir -p "$drift_home"
"$install_script" --target-home "$drift_home" --apply \
  >"$test_root/drift-setup-output" 2>&1
printf '%s\n' '{"version":"4.6.1"}' \
  >"$drift_home/.pi/agent/software-factory/pi-permission-runtime/node_modules/zod/package.json"

set +e
"$install_script" --target-home "$drift_home" \
  >"$test_root/drift-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'dependency drift inspect'
grep -Fq 'installed package version differs from lock: zod' \
  "$test_root/drift-output" ||
  fail 'dependency drift did not name the changed package'

printf '%s\n' 'PASS: install-pi-permissions critical tests'
