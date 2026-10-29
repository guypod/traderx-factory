#!/usr/bin/env bash
# Prerequisite doctor for state 001 (baseline uncontainerized).
# Read-only: it only runs version/listing commands. It never installs packages,
# uses sudo, touches the network, or starts TraderX processes.
set -uo pipefail

usage() {
  cat <<'EOF'
usage: ./scripts/doctor-base-uncontainerized-prerequisites.sh

Checks the local toolchain needed to generate, build and run state 001:
  - Gradle build JDK 21-24 (java and javac, same major version; JAVA_HOME when
    set, otherwise PATH). Gradle 8.14.x cannot run on Java 25+.
  - java 21+ on PATH, which starts the services with bare 'java -jar'
  - Node.js ^20.19 || ^22.12 || >=24 and npm
  - .NET SDK 9.x plus Microsoft.NETCore.App / Microsoft.AspNetCore.App 9.x runtimes
  - rsync, nc (netcat with -z), jq, curl

A probe passes only when its command exits 0 and prints the expected version
line; output from a failed command is never trusted.

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

# Repository or generated-checkout root, resolved with builtins only.
SCRIPT_DIR="."
[[ "${BASH_SOURCE[0]}" == */* ]] && SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The Gradle wrapper pinned in templates/gradle-wrapper (8.14.x) runs on Java 21-24;
# Java 25 needs Gradle 9.1+. Raise this together with the wrapper.
JAVA_MIN=21
GRADLE_MAX_JAVA=24

BLOCKERS=0
WARNINGS=0

ok() { echo "[ok] $*"; }
warn() { echo "[warn] $*"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "[fail] $*"; BLOCKERS=$((BLOCKERS + 1)); }
hint() { echo "[hint] $*"; }

# Java reports legacy versions as 1.8.0; map those to their major (8).
java_major() {
  local v="$1" major
  major="${v%%.*}"
  if [[ "${major}" == "1" ]]; then
    major="$(cut -d. -f2 <<<"${v}")"
  fi
  echo "${major}"
}

# Prints the version from '<java> -version' only when the command exits 0 and
# prints a genuine 'openjdk version "X"' / 'java version "X"' line. Diagnostic
# lines such as 'Picked up JAVA_TOOL_OPTIONS: -Dapp.version=21.0.0' are ignored.
probe_java_version() {
  local out
  out="$("$1" -version 2>&1)" || return 1
  grep -Eo '^(openjdk|java) version "[0-9]+(\.[0-9]+)*' <<<"${out}" | head -n 1 | sed -E 's/.*"//'
}

# Prints the version from '<javac> -version' only on exit 0 and a 'javac X' line.
probe_javac_version() {
  local out
  out="$("$1" -version 2>&1)" || return 1
  grep -Eo '^javac [0-9]+(\.[0-9]+)*' <<<"${out}" | head -n 1 | cut -d' ' -f2
}

java_install_hint() {
  hint "install a JDK ${JAVA_MIN} (for example Eclipse Temurin 21) and put its bin/ on PATH or set JAVA_HOME"
}

check_java() {
  local build_java build_javac runtime_java source
  runtime_java="$(command -v java || true)"
  if [[ -n "${JAVA_HOME:-}" ]]; then
    build_java="${JAVA_HOME}/bin/java"
    build_javac="${JAVA_HOME}/bin/javac"
    source="JAVA_HOME (${JAVA_HOME}/bin)"
    echo "[info] JAVA_HOME is set; Gradle will use ${JAVA_HOME}, services start with the java on PATH"
  else
    build_java="${runtime_java}"
    build_javac="$(command -v javac || true)"
    source="PATH"
  fi

  # Build JDK runtime (the JVM Gradle runs on).
  local java_ver="" java_maj=""
  if [[ -z "${build_java}" || ! -x "${build_java}" ]]; then
    fail "java not found in ${source}"
    java_install_hint
  elif ! java_ver="$(probe_java_version "${build_java}")" || [[ -z "${java_ver}" ]]; then
    java_ver=""
    fail "'${build_java} -version' failed or printed no Java version line"
    hint "check that ${build_java} runs on this machine and architecture, and that JAVA_TOOL_OPTIONS/JDK_JAVA_OPTIONS are valid"
  else
    java_maj="$(java_major "${java_ver}")"
    if (( java_maj < JAVA_MIN )); then
      fail "java ${java_ver} is too old; the Java services target Java ${JAVA_MIN} (sourceCompatibility ${JAVA_MIN})"
      hint "install a JDK ${JAVA_MIN}-${GRADLE_MAX_JAVA} and make it first on PATH or set JAVA_HOME"
    elif (( java_maj > GRADLE_MAX_JAVA )); then
      fail "java ${java_ver} is too new for the Gradle 8.14 wrapper, which runs on Java ${JAVA_MIN}-${GRADLE_MAX_JAVA}"
      hint "use a JDK ${JAVA_MIN}-${GRADLE_MAX_JAVA} for builds (set JAVA_HOME to it)"
    else
      ok "java ${java_ver} (${build_java}, Gradle build JDK)"
    fi
  fi

  # Build JDK compiler; checked even when the runtime above is missing.
  local javac_ver javac_maj
  if [[ -z "${build_javac}" || ! -x "${build_javac}" ]]; then
    if [[ -n "${java_ver}" ]]; then
      fail "javac not found: ${build_java} looks like a JRE, but Gradle builds need a JDK compiler"
    else
      fail "javac not found in ${source}; Gradle builds need a JDK compiler"
    fi
    hint "install a full JDK ${JAVA_MIN} (not a JRE) and put its bin/ on PATH or set JAVA_HOME"
  elif ! javac_ver="$(probe_javac_version "${build_javac}")" || [[ -z "${javac_ver}" ]]; then
    fail "'${build_javac} -version' failed or printed no javac version line"
  else
    javac_maj="$(java_major "${javac_ver}")"
    if (( javac_maj < JAVA_MIN )); then
      fail "javac ${javac_ver} is too old; Java ${JAVA_MIN} sources need javac ${JAVA_MIN}+"
      hint "install a JDK ${JAVA_MIN}-${GRADLE_MAX_JAVA} and make it first on PATH or set JAVA_HOME"
    elif (( javac_maj > GRADLE_MAX_JAVA )); then
      fail "javac ${javac_ver} is too new for the Gradle 8.14 wrapper, which runs on Java ${JAVA_MIN}-${GRADLE_MAX_JAVA}"
      hint "use a JDK ${JAVA_MIN}-${GRADLE_MAX_JAVA} for builds (set JAVA_HOME to it)"
    elif [[ -n "${java_maj}" ]] && (( javac_maj != java_maj )); then
      fail "javac ${javac_ver} and java ${java_ver} come from different JDKs"
      hint "use one JDK ${JAVA_MIN}+ for both: point PATH or JAVA_HOME at a single JDK bin/"
    else
      ok "javac ${javac_ver} (${build_javac})"
    fi
  fi

  # Service runtime: the process catalog starts Java services with bare
  # 'java -jar', which resolves through PATH and ignores JAVA_HOME.
  if [[ -n "${JAVA_HOME:-}" ]]; then
    local run_ver run_maj
    if [[ -z "${runtime_java}" ]]; then
      fail "java not found on PATH; services start with bare 'java -jar', which does not use JAVA_HOME"
      hint "add ${JAVA_HOME}/bin to PATH"
    elif [[ "${runtime_java}" -ef "${build_java}" ]]; then
      ok "java on PATH is the JAVA_HOME java (service runtime)"
    elif ! run_ver="$(probe_java_version "${runtime_java}")" || [[ -z "${run_ver}" ]]; then
      fail "'${runtime_java} -version' failed or printed no Java version line (java on PATH starts the services)"
      hint "add ${JAVA_HOME}/bin to the front of PATH"
    else
      run_maj="$(java_major "${run_ver}")"
      if (( run_maj < JAVA_MIN )); then
        fail "java ${run_ver} on PATH (${runtime_java}) is too old to run the services; JAVA_HOME only affects Gradle"
        hint "add ${JAVA_HOME}/bin to the front of PATH"
      else
        ok "java ${run_ver} on PATH (${runtime_java}, service runtime)"
      fi
    fi
  fi
}

check_node() {
  local out
  if ! command -v node >/dev/null 2>&1; then
    fail "node not found"
    hint "install Node.js 22 LTS (supported: ^20.19 || ^22.12 || >=24, required by Angular 20)"
  elif ! out="$(node --version 2>&1)" || ! [[ "${out}" =~ ^v([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    fail "'node --version' failed or did not print a vX.Y.Z version"
    hint "check that node runs on this machine; reinstall Node.js 22 LTS if needed"
  else
    local ver="${out#v}" major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}"
    if (( major >= 24 )) || { (( major == 22 )) && (( minor >= 12 )); } || { (( major == 20 )) && (( minor >= 19 )); }; then
      ok "node ${ver}"
    else
      fail "node ${ver} is not supported by the Angular 20 front end"
      hint "install Node.js 22 LTS (supported: ^20.19 || ^22.12 || >=24)"
    fi
  fi

  if ! command -v npm >/dev/null 2>&1; then
    fail "npm not found"
    hint "npm ships with Node.js; reinstall Node.js 22 LTS or add its bin/ to PATH"
  elif ! out="$(npm --version 2>/dev/null)" || ! [[ "${out}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    fail "'npm --version' failed or did not print an X.Y.Z version"
    hint "reinstall Node.js 22 LTS so npm matches it"
  else
    ok "npm ${out}"
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
  if ! sdks="$(dotnet --list-sdks 2>/dev/null)"; then
    fail "'dotnet --list-sdks' failed, so the .NET SDK 9.x cannot be confirmed"
    hint "repair or reinstall the .NET 9 SDK for this CPU architecture"
  elif grep -Eq '^9\.[0-9]+\.[0-9]+ \[' <<<"${sdks}"; then
    ok "dotnet SDK $(grep -E '^9\.[0-9]+\.[0-9]+ \[' <<<"${sdks}" | head -n 1 | cut -d' ' -f1)"
  else
    fail ".NET SDK 9.x not found (found: $(cut -d' ' -f1 <<<"${sdks}" | tr '\n' ' ' | sed 's/ *$//;s/^$/none/'))"
    hint "'dotnet build' for people-service needs the .NET 9 SDK, not only a runtime"
  fi

  if ! runtimes="$(dotnet --list-runtimes 2>/dev/null)"; then
    fail "'dotnet --list-runtimes' failed, so the .NET 9 runtimes cannot be confirmed"
    hint "repair or reinstall the .NET 9 SDK for this CPU architecture"
    return
  fi
  local runtime
  for runtime in Microsoft.NETCore.App Microsoft.AspNetCore.App; do
    if grep -Eq "^${runtime} 9\.[0-9]+\.[0-9]+ \[" <<<"${runtimes}"; then
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

# Startup waits on 'nc -z localhost <port>'. Confirm -z is supported without
# touching the network: 'nc -h' only prints usage (BSD/OpenBSD/BusyBox all list
# their flags there), so a usage text that never mentions -z is a blocker.
check_netcat() {
  local install_hint="install a netcat that supports -z (for example 'apt-get install netcat-openbsd'; macOS ships nc)"
  if ! command -v nc >/dev/null 2>&1; then
    fail "nc not found (used by start/status scripts to probe service ports with 'nc -z')"
    hint "${install_hint}"
    return
  fi
  local help
  help="$(nc -h 2>&1 </dev/null || true)"
  if grep -Eq '(^|[[:space:][])-[[:alnum:]]*z([],[:space:]]|$)' <<<"${help}"; then
    ok "nc ($(command -v nc), supports -z)"
  else
    fail "nc ($(command -v nc)) does not list -z in 'nc -h'; start/status port probes need 'nc -z'"
    hint "${install_hint}"
  fi
}

echo "TraderX state 001 prerequisite doctor (read-only; no installs, no network, no startup)"
check_java
check_node
check_dotnet
check_simple_tool rsync "used by state generation to copy the Angular front end" \
  "install rsync with your OS package manager (for example 'brew install rsync' or 'apt-get install rsync')"
check_netcat
check_simple_tool jq "used by state generation to read catalog/state-catalog.json" \
  "install jq with your OS package manager"
if [[ "${TRADERSPEC_SKIP_NETWORK_CHECK:-0}" == "1" ]]; then
  # FR-025 exception: with the start script's network preflight skipped, curl is not used.
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
if [[ -f "${ROOT}/pipeline/generate-state.sh" ]]; then
  next="bash pipeline/generate-state.sh 001-baseline-uncontainerized-parity, then ./scripts/start-base-uncontainerized-generated.sh --build-only"
else
  # Generated checkout: already generated, so build directly.
  next="./scripts/start-base-uncontainerized-generated.sh --build-only"
fi
echo "[result] no blockers (${WARNINGS} warning(s)). Next: ${next}"
exit 0
