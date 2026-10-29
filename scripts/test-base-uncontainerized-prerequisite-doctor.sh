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
  stub "${dir}" nc 'echo "usage: nc [-46DdhklnrStUuvz] [-p source_port] destination port" >&2; exit 1'
  stub "${dir}" jq 'exit 0'
  stub "${dir}" curl 'exit 0'
}

# run_case <name> <expected-exit> <expected-pattern> [setup-command...]
# Setup commands receive the stub bin dir and may append VAR=value lines to
# "${bin}/../env" to pass extra environment to the doctor.
run_case() {
  local name="$1" expected_exit="$2" pattern="$3"
  shift 3
  local bin="${WORK}/${name}/bin"
  make_healthy_bin "${bin}"
  : > "${WORK}/${name}/env"
  if (( $# > 0 )); then
    "$@" "${bin}"
  fi

  local doctor="${DOCTOR}" extra_env=()
  mapfile -t extra_env < "${WORK}/${name}/env"
  if [[ -f "${WORK}/${name}/doctor-root" ]]; then
    doctor="$(cat "${WORK}/${name}/doctor-root")/scripts/$(basename "${DOCTOR}")"
  fi

  local out status=0
  out="$(env -i PATH="${bin}" HOME="${WORK}" "${extra_env[@]}" "${BASH_BIN}" "${doctor}" 2>&1)" || status=$?
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

set_env() { echo "$2" >> "${1}/../env"; }

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

# Probes must succeed: plausible version output with a nonzero exit is a blocker.
node_fails_with_version() { stub "$1" node 'echo "v22.12.0"; exit 1'; }
npm_fails_with_version() { stub "$1" npm 'echo "10.9.0"; exit 1'; }
java_fails_with_version() {
  stub "$1" java 'echo "openjdk version \"21.0.4\" 2024-07-16" >&2; exit 1'
}
javac_fails_with_version() { stub "$1" javac 'echo "javac 21.0.4"; exit 2'; }
# A JVM that fails on bad JAVA_TOOL_OPTIONS still echoes the options, which
# contain digits and the word "version".
java_tool_options_failure() {
  stub "$1" java 'echo "Picked up JAVA_TOOL_OPTIONS: -Dapp.version=21.0.0 -XX:NotARealOption" >&2
echo "Unrecognized VM option NotARealOption" >&2; exit 1'
  stub "$1" javac 'echo "Picked up JAVA_TOOL_OPTIONS: -Dapp.version=21.0.0" >&2; echo "error: invalid flag" >&2; exit 2'
}
# Misleading numeric stderr with exit 0 but no genuine version line.
java_misleading_stderr() {
  stub "$1" java 'echo "Error: version 21.0.0 of libjli could not be loaded" >&2; exit 0'
}
node_misleading_stderr() { stub "$1" node 'echo "node: error loading lib v22.12.0" >&2; exit 0'; }
dotnet_list_sdks_fails() {
  stub "$1" dotnet 'case "$1" in
  --version) echo "9.0.100" ;;
  --list-sdks) echo "9.0.100 [/usr/share/dotnet/sdk]"; exit 1 ;;
  --list-runtimes)
    echo "Microsoft.AspNetCore.App 9.0.0 [/x]"
    echo "Microsoft.NETCore.App 9.0.0 [/x]" ;;
esac'
}
dotnet_list_runtimes_fails() {
  stub "$1" dotnet 'case "$1" in
  --version) echo "9.0.100" ;;
  --list-sdks) echo "9.0.100 [/usr/share/dotnet/sdk]" ;;
  --list-runtimes)
    echo "Microsoft.AspNetCore.App 9.0.0 [/x]"
    echo "Microsoft.NETCore.App 9.0.0 [/x]"; exit 1 ;;
esac'
}

run_case node-version-nonzero-exit 1 "'node --version' failed" node_fails_with_version
run_case npm-version-nonzero-exit 1 "'npm --version' failed" npm_fails_with_version
run_case java-version-nonzero-exit 1 "java -version' failed" java_fails_with_version
run_case javac-version-nonzero-exit 1 "javac -version' failed" javac_fails_with_version
run_case java-tool-options-failure 1 '\[result\] 2 blocker\(s\)' java_tool_options_failure
run_case java-misleading-stderr 1 "java -version' failed or printed no Java version line" java_misleading_stderr
run_case node-misleading-stderr 1 "'node --version' failed" node_misleading_stderr
run_case dotnet-list-sdks-nonzero-exit 1 "'dotnet --list-sdks' failed" dotnet_list_sdks_fails
run_case dotnet-list-runtimes-nonzero-exit 1 "'dotnet --list-runtimes' failed" dotnet_list_runtimes_fails

# Missing java still reports the independently missing javac.
no_java_no_javac() { remove java "$1"; remove javac "$1"; }
run_case missing-java-and-javac 1 '\[result\] 2 blocker\(s\)' no_java_no_javac

# The Gradle 8.14 wrapper cannot run on Java 25+.
java_25() {
  stub "$1" java 'echo "openjdk version \"25\" 2025-09-16" >&2'
  stub "$1" javac 'echo "javac 25"'
}
run_case java-25-exceeds-gradle 1 'java 25 is too new for the Gradle 8\.14 wrapper' java_25

# JAVA_HOME selects the Gradle JDK, but services start with the java on PATH.
make_jdk() {
  local home="$1" ver="$2"
  mkdir -p "${home}/bin"
  stub "${home}/bin" java "echo \"openjdk version \\\"${ver}\\\" 2024-07-16\" >&2"
  stub "${home}/bin" javac "echo \"javac ${ver}\""
}
java_home_jdk21_path_java8() {
  local home="$1/../jdk21"
  make_jdk "${home}" 21.0.4
  old_java "$1"
  set_env "$1" "JAVA_HOME=${home}"
}
java_home_jdk21_no_path_java() {
  local home="$1/../jdk21"
  make_jdk "${home}" 21.0.4
  remove java "$1"; remove javac "$1"
  set_env "$1" "JAVA_HOME=${home}"
}
java_home_jdk21_path_same() {
  local home="$1/../jdk21"
  make_jdk "${home}" 21.0.4
  ln -sf "${home}/bin/java" "$1/java"; ln -sf "${home}/bin/javac" "$1/javac"
  set_env "$1" "JAVA_HOME=${home}"
}
java_home_jdk8_path_jdk21() {
  local home="$1/../jdk8"
  make_jdk "${home}" 1.8.0_402
  set_env "$1" "JAVA_HOME=${home}"
}
run_case java-home-21-path-java-8 1 'java 1\.8\.0 on PATH .* is too old to run the services' java_home_jdk21_path_java8
run_case java-home-21-no-path-java 1 "java not found on PATH; services start with bare 'java -jar'" java_home_jdk21_no_path_java
run_case java-home-21-path-same-jdk 0 'java on PATH is the JAVA_HOME java' java_home_jdk21_path_same
run_case java-home-8-path-jdk-21 1 'java 1\.8\.0 is too old' java_home_jdk8_path_jdk21

# nc must support the -z probe used by wait_for_port.
nc_without_z() { stub "$1" nc 'echo "usage: nc [-lnuv] [-p port] host port" >&2; exit 1'; }
run_case netcat-without-z 1 "does not list -z" nc_without_z

# curl: a blocker by default, a warning only under TRADERSPEC_SKIP_NETWORK_CHECK=1.
no_curl() { remove curl "$1"; }
no_curl_skip_network() { remove curl "$1"; set_env "$1" "TRADERSPEC_SKIP_NETWORK_CHECK=1"; }
run_case missing-curl 1 '\[fail\] curl not found' no_curl
run_case missing-curl-network-check-skipped 0 '\[warn\] curl not found' no_curl_skip_network

# Next-step guidance must work in source and generated checkouts.
run_case next-step-source-checkout 0 'Next: bash pipeline/generate-state\.sh 001'
generated_checkout() {
  local root="$1/../generated-root"
  mkdir -p "${root}/scripts"
  cp "${DOCTOR}" "${root}/scripts/"
  echo "${root}" > "$1/../doctor-root"
}
run_case next-step-generated-checkout 0 'Next: \./scripts/start-base-uncontainerized-generated\.sh --build-only$' generated_checkout

# The doctor must stay read-only: no package managers, sudo or app startup.
if grep -Eq '\b(sudo|apt-get install|brew install|yum install|dnf install|npm (install|ci)|\./gradlew|dotnet (build|run))\b' \
  <(grep -Ev '^\s*#' "${DOCTOR}" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g"); then
  fail "doctor contains an install, privileged or startup command outside quoted guidance text"
fi
echo "[ok] doctor executes no install, privileged or startup commands"

echo "[ok] prerequisite doctor checks passed (${PASSED} scenarios)"
