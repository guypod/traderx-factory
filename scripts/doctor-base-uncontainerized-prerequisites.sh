#!/usr/bin/env bash
# Prerequisite doctor for state 001 (baseline uncontainerized).
# Read-only: it only runs version/listing commands. It never installs packages,
# uses sudo, touches the network, or starts TraderX processes.
set -uo pipefail

usage() {
  cat <<'EOF'
usage: ./scripts/doctor-base-uncontainerized-prerequisites.sh

Checks the local toolchain needed to generate, build and run state 001:
  - JDK 21+ (java runtime and javac compiler, same major version)
  - Node.js ^20.19 || ^22.12 || >=24 and npm
  - .NET SDK 9.x plus Microsoft.NETCore.App / Microsoft.AspNetCore.App 9.x runtimes
  - rsync, nc (netcat), jq, curl

Exit status: 0 when no blockers were found, 1 when at least one blocker was found.
Set TRADERSPEC_SKIP_NETWORK_CHECK=1 to downgrade a missing curl to a warning
(matching the start script, which only needs curl for its network preflight).
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) echo "[error] unknown argument: $1"; usage; exit 2 ;;
esac

BLOCKERS=0
WARNINGS=0

ok() { echo "[ok] $*"; }
warn() { echo "[warn] $*"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "[fail] $*"; BLOCKERS=$((BLOCKERS + 1)); }
hint() { echo "[hint] $*"; }

# Extract the first dotted version number (for example 21.0.2 or 1.8.0) from text.
first_version() {
  grep -Eo '[0-9]+(\.[0-9]+)+|[0-9]+' <<<"$1" | head -n 1
}

# Java reports legacy versions as 1.8.0; map those to their major (8).
java_major() {
  local v="$1" major
  major="${v%%.*}"
  if [[ "${major}" == "1" ]]; then
    major="$(cut -d. -f2 <<<"${v}")"
  fi
  echo "${major}"
}

check_java() {
  local java_cmd javac_cmd
  if [[ -n "${JAVA_HOME:-}" ]]; then
    java_cmd="${JAVA_HOME}/bin/java"
    javac_cmd="${JAVA_HOME}/bin/javac"
    echo "[info] JAVA_HOME is set; Gradle will use ${JAVA_HOME}"
  else
    java_cmd="$(command -v java || true)"
    javac_cmd="$(command -v javac || true)"
  fi

  if [[ -z "${java_cmd}" || ! -x "${java_cmd}" ]]; then
    fail "java not found${JAVA_HOME:+ in JAVA_HOME (${JAVA_HOME}/bin/java)}"
    hint "install a JDK 21 (for example Eclipse Temurin 21) and put its bin/ on PATH or set JAVA_HOME"
    return
  fi

  local java_out java_ver java_maj
  java_out="$("${java_cmd}" -version 2>&1 || true)"
  java_ver="$(first_version "$(grep -i 'version' <<<"${java_out}" | head -n 1)")"
  if [[ -z "${java_ver}" ]]; then
    fail "could not read a version from '${java_cmd} -version'"
    hint "check that ${java_cmd} runs on this machine and architecture"
    return
  fi
  java_maj="$(java_major "${java_ver}")"
  if (( java_maj < 21 )); then
    fail "java ${java_ver} is too old; the Java services target Java 21 (sourceCompatibility 21)"
    hint "install a JDK 21+ and make it first on PATH or set JAVA_HOME"
  else
    ok "java ${java_ver} (${java_cmd})"
  fi

  if [[ -z "${javac_cmd}" || ! -x "${javac_cmd}" ]]; then
    fail "javac not found: ${java_cmd} looks like a JRE, but Gradle builds need a JDK compiler"
    hint "install a full JDK 21 (not a JRE) and put its bin/ on PATH or set JAVA_HOME"
    return
  fi

  local javac_out javac_ver javac_maj
  javac_out="$("${javac_cmd}" -version 2>&1 || true)"
  javac_ver="$(first_version "${javac_out}")"
  if [[ -z "${javac_ver}" ]]; then
    fail "could not read a version from '${javac_cmd} -version'"
    return
  fi
  javac_maj="$(java_major "${javac_ver}")"
  if (( javac_maj < 21 )); then
    fail "javac ${javac_ver} is too old; Java 21 sources need javac 21+"
    hint "install a JDK 21+ and make it first on PATH or set JAVA_HOME"
  elif (( javac_maj != java_maj )); then
    fail "javac ${javac_ver} and java ${java_ver} come from different JDKs"
    hint "use one JDK 21+ for both: point PATH or JAVA_HOME at a single JDK bin/"
  else
    ok "javac ${javac_ver} (${javac_cmd})"
  fi
}

check_node() {
  if ! command -v node >/dev/null 2>&1; then
    fail "node not found"
    hint "install Node.js 22 LTS (supported: ^20.19 || ^22.12 || >=24, required by Angular 20)"
  else
    local ver major minor rest supported=0
    ver="$(first_version "$(node --version 2>&1 || true)")"
    major="${ver%%.*}"
    rest="${ver#*.}"
    minor="${rest%%.*}"
    if [[ -z "${ver}" || "${major}" == "${ver}" ]]; then
      fail "could not read a version from 'node --version'"
    else
      if (( major >= 24 )) || { (( major == 22 )) && (( minor >= 12 )); } || { (( major == 20 )) && (( minor >= 19 )); }; then
        supported=1
      fi
      if (( supported )); then
        ok "node ${ver}"
      else
        fail "node ${ver} is not supported by the Angular 20 front end"
        hint "install Node.js 22 LTS (supported: ^20.19 || ^22.12 || >=24)"
      fi
    fi
  fi

  if ! command -v npm >/dev/null 2>&1; then
    fail "npm not found"
    hint "npm ships with Node.js; reinstall Node.js 22 LTS or add its bin/ to PATH"
  else
    local npm_ver
    npm_ver="$(first_version "$(npm --version 2>&1 || true)")"
    if [[ -z "${npm_ver}" ]]; then
      fail "could not read a version from 'npm --version'"
    else
      ok "npm ${npm_ver}"
    fi
  fi
}

check_dotnet() {
  if ! command -v dotnet >/dev/null 2>&1; then
    fail "dotnet not found (people-service targets net9.0)"
    hint "install the .NET 9 SDK, which includes the ASP.NET Core 9 runtime"
    return
  fi
  if ! dotnet --version >/dev/null 2>&1; then
    fail "dotnet is installed but not runnable on this machine"
    hint "install a native .NET 9 SDK for this CPU architecture (or enable x64 emulation)"
    return
  fi

  local sdks runtimes
  sdks="$(dotnet --list-sdks 2>/dev/null || true)"
  runtimes="$(dotnet --list-runtimes 2>/dev/null || true)"

  if grep -Eq '^9\.' <<<"${sdks}"; then
    ok "dotnet SDK $(grep -E '^9\.' <<<"${sdks}" | head -n 1 | cut -d' ' -f1)"
  else
    fail ".NET SDK 9.x not found (found: $(cut -d' ' -f1 <<<"${sdks}" | tr '\n' ' ' | sed 's/ *$//;s/^$/none/'))"
    hint "'dotnet build' for people-service needs the .NET 9 SDK, not only a runtime"
  fi

  local runtime
  for runtime in Microsoft.NETCore.App Microsoft.AspNetCore.App; do
    if grep -Eq "^${runtime} 9\." <<<"${runtimes}"; then
      ok "${runtime} $(grep -E "^${runtime} 9\." <<<"${runtimes}" | head -n 1 | cut -d' ' -f2)"
    else
      fail "${runtime} 9.x runtime not found"
      hint "install the .NET 9 SDK (or the ASP.NET Core Runtime 9) for this CPU architecture"
    fi
  done
}

check_simple_tool() {
  local cmd="$1" purpose="$2" install_hint="$3" severity="${4:-fail}"
  if command -v "${cmd}" >/dev/null 2>&1; then
    ok "${cmd} ($(command -v "${cmd}"))"
  elif [[ "${severity}" == "warn" ]]; then
    warn "${cmd} not found (${purpose})"
    hint "${install_hint}"
  else
    fail "${cmd} not found (${purpose})"
    hint "${install_hint}"
  fi
}

echo "TraderX state 001 prerequisite doctor (read-only; no installs, no network, no startup)"
check_java
check_node
check_dotnet
check_simple_tool rsync "used by state generation to copy the Angular front end" \
  "install rsync with your OS package manager (for example 'brew install rsync' or 'apt-get install rsync')"
check_simple_tool nc "used by start/status scripts to probe service ports with 'nc -z'" \
  "install a netcat that supports -z (for example 'apt-get install netcat-openbsd'; macOS ships nc)"
check_simple_tool jq "used by state generation to read catalog/state-catalog.json" \
  "install jq with your OS package manager"
if [[ "${TRADERSPEC_SKIP_NETWORK_CHECK:-0}" == "1" ]]; then
  check_simple_tool curl "start script network preflight is skipped by TRADERSPEC_SKIP_NETWORK_CHECK=1" \
    "install curl if you later run with the network preflight enabled" warn
else
  check_simple_tool curl "used by the start script's Gradle/Maven network preflight" \
    "install curl, or set TRADERSPEC_SKIP_NETWORK_CHECK=1 only if dependencies are already cached"
fi

echo
if (( BLOCKERS > 0 )); then
  echo "[result] ${BLOCKERS} blocker(s), ${WARNINGS} warning(s): fix the [fail] lines above before building state 001"
  exit 1
fi
echo "[result] no blockers (${WARNINGS} warning(s)). Next: bash pipeline/generate-state.sh 001-baseline-uncontainerized-parity, then ./scripts/start-base-uncontainerized-generated.sh --build-only"
exit 0
