#!/usr/bin/env bash
# Exercises scripts/doctor-base-uncontainerized-prerequisites.sh against isolated
# stub executables so available, missing and incompatible toolchains are tested
# without depending on (or changing) the host toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="${ROOT}/scripts/doctor-base-uncontainerized-prerequisites.sh"
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PASSED=0

fail() {
  echo "[fail] $*"
  exit 1
}

# Shell utilities the doctor itself relies on; linked into every stub PATH.
BASE_UTILS=(grep head cut sed tr)

stub() {
  local dir="$1" name="$2" body="$3"
  printf '#!%s\n%s\n' "${BASH_BIN}" "${body}" > "${dir}/${name}"
  chmod +x "${dir}/${name}"
}

# Builds a PATH directory with a healthy toolchain; callers then remove or
# replace individual stubs to model a scenario.
make_healthy_bin() {
  local dir="$1" util
  mkdir -p "${dir}"
  for util in "${BASE_UTILS[@]}"; do
    ln -s "$(command -v "${util}")" "${dir}/${util}"
  done
  stub "${dir}" java 'echo "openjdk version \"21.0.4\" 2024-07-16" >&2'
  stub "${dir}" javac 'echo "javac 21.0.4"'
  stub "${dir}" node 'echo "v22.12.0"'
  stub "${dir}" npm 'echo "10.9.0"'
  stub "${dir}" dotnet 'case "$1" in
  --version) echo "9.0.100" ;;
  --list-sdks) echo "9.0.100 [/usr/share/dotnet/sdk]" ;;
  --list-runtimes)
    echo "Microsoft.AspNetCore.App 9.0.0 [/usr/share/dotnet/shared/Microsoft.AspNetCore.App]"
    echo "Microsoft.NETCore.App 9.0.0 [/usr/share/dotnet/shared/Microsoft.NETCore.App]" ;;
esac'
  stub "${dir}" rsync 'exit 0'
  stub "${dir}" nc 'exit 0'
  stub "${dir}" jq 'exit 0'
  stub "${dir}" curl 'exit 0'
}

# run_case <name> <expected-exit> <expected-pattern> [setup-command...]
run_case() {
  local name="$1" expected_exit="$2" pattern="$3"
  shift 3
  local bin="${WORK}/${name}/bin"
  make_healthy_bin "${bin}"
  if (( $# > 0 )); then
    "$@" "${bin}"
  fi

  local out status=0
  out="$(env -i PATH="${bin}" HOME="${WORK}" "${BASH_BIN}" "${DOCTOR}" 2>&1)" || status=$?
  if [[ "${status}" != "${expected_exit}" ]]; then
    echo "${out}"
    fail "${name}: expected exit ${expected_exit}, got ${status}"
  fi
  if ! grep -Eq -- "${pattern}" <<<"${out}"; then
    echo "${out}"
    fail "${name}: output did not match /${pattern}/"
  fi
  echo "[ok] ${name}"
  PASSED=$((PASSED + 1))
}

remove() { local tool="$1" dir="$2"; rm -f "${dir}/${tool}"; }
jre_only() { remove javac "$1"; }
no_rsync() { remove rsync "$1"; }
no_nc() { remove nc "$1"; }
no_npm() { remove npm "$1"; }
no_dotnet() { remove dotnet "$1"; }
old_java() {
  stub "$1" java 'echo "java version \"1.8.0_402\"" >&2'
  stub "$1" javac 'echo "javac 1.8.0_402"'
}
mixed_jdk() { stub "$1" javac 'echo "javac 22.0.2"'; }
old_node() { stub "$1" node 'echo "v18.20.4"'; }
runtime_only_dotnet() {
  stub "$1" dotnet 'case "$1" in
  --version) echo "8.0.100" ;;
  --list-sdks) echo "8.0.100 [/usr/share/dotnet/sdk]" ;;
  --list-runtimes) echo "Microsoft.NETCore.App 9.0.0 [/usr/share/dotnet/shared/Microsoft.NETCore.App]" ;;
esac'
}
broken_dotnet() { stub "$1" dotnet 'exit 134'; }

run_case healthy-toolchain 0 '\[result\] no blockers'
run_case jre-without-javac 1 'javac not found: .* looks like a JRE' jre_only
run_case java-8 1 'java 1\.8\.0 is too old' old_java
run_case mixed-jdk-versions 1 'javac 22\.0\.2 and java 21\.0\.4 come from different JDKs' mixed_jdk
run_case node-18 1 'node 18\.20\.4 is not supported' old_node
run_case missing-npm 1 '\[fail\] npm not found' no_npm
run_case missing-dotnet 1 '\[fail\] dotnet not found' no_dotnet
run_case unrunnable-dotnet 1 'dotnet is installed but not runnable' broken_dotnet
run_case dotnet-sdk-8-without-aspnet-9 1 '\.NET SDK 9\.x not found.*' runtime_only_dotnet
run_case missing-rsync 1 '\[fail\] rsync not found' no_rsync
run_case missing-netcat 1 '\[fail\] nc not found' no_nc

# Every blocker is reported in one pass, not just the first.
both_missing() { remove rsync "$1"; remove nc "$1"; }
run_case reports-all-blockers 1 '\[result\] 2 blocker\(s\)' both_missing

# The doctor must stay read-only: no package managers, sudo or app startup.
if grep -Eq '\b(sudo|apt-get install|brew install|yum install|dnf install|npm (install|ci)|\./gradlew|dotnet (build|run))\b' \
  <(grep -Ev '^\s*#' "${DOCTOR}" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g"); then
  fail "doctor contains an install, privileged or startup command outside quoted guidance text"
fi
echo "[ok] doctor executes no install, privileged or startup commands"

echo "[ok] prerequisite doctor checks passed (${PASSED} scenarios)"
