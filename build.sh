#!/bin/bash
set -e
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
MVNW="cn1_mvnw"

# --- first-build signals ------------------------------------------------------
# Tells cloud.codenameone.com when this starter starts a build and how Maven
# exited, so a first build that dies on this machine (no JDK, an old JDK, a Maven
# download, a compile error, a sign-in that timed out) is visible to us instead
# of silent. Sends ONLY: this starter's package id, the target, the OS family,
# the Java major version, the exit code, one word for the failure class and the
# duration. Never your code, paths, user name or build output.
# Opt out with CN1_TELEMETRY=0.
CN1_STARTER_PACKAGE="co.cn1.my.first.app.dp3oo5vf"
CN1_EVENTS_URL="${CN1_EVENTS_URL:-https://cloud.codenameone.com/api/v2/onboarding/starter-event}"
# Maven reports IDE builds itself (cn1.telemetry.* in pom.xml); this tells it the
# launcher is already reporting this one, so it is counted once.
export CN1_LAUNCHER=1

function cn1_event {
  [ "${CN1_TELEMETRY:-1}" = "0" ] && return 0
  command -v curl >/dev/null 2>&1 || return 0
  curl -s -o /dev/null -m 3 -X POST "$CN1_EVENTS_URL" \
    --data-urlencode "pkg=$CN1_STARTER_PACKAGE" "$@" >/dev/null 2>&1 || true
}

function cn1_os {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo mac ;;
    Linux) if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo other ;;
  esac
}

function cn1_java_major {
  local java="java"
  [ -n "${JAVA_HOME-}" ] && java="$JAVA_HOME/bin/java"
  local v
  v="$("$java" -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n 1)" || true
  if [ -z "$v" ]; then echo none; return; fi
  case "$v" in
    1.*) v="${v#1.}" ;;
  esac
  v="${v%%[!0-9]*}"
  echo "${v:-unknown}"
}

# One word for why Maven stopped, matched against its own output.
function cn1_reason {
  local code="$1" log="$2"
  if [ "$code" = "0" ]; then echo ok; return; fi
  if grep -qE "JAVA_HOME environment variable is not defined correctly|java/javac command does not exist" "$log"; then echo no_jdk
  elif grep -qE "invalid target release|release version [0-9]+ not supported|UnsupportedClassVersionError|class file version" "$log"; then echo java_too_old
  elif grep -qE "Browser login timed out" "$log"; then echo login_timeout
  elif grep -qE "Browser login failed|Could not complete browser login" "$log"; then echo login_failed
  elif grep -qE "COMPILATION ERROR" "$log"; then echo compile
  elif grep -qE "Could not resolve dependencies|Could not transfer artifact|Could not download|UnknownHostException|Connection timed out|Failed to fetch" "$log"; then echo maven_download
  elif grep -qE "BUILD FAILURE" "$log"; then echo build_failed
  else echo unknown
  fi
}

# Stops a process AND everything it started, children first. Killing only the
# wrapper's pid left its children -- the curl/unzip of a first run's Maven
# download, a forked JVM -- holding the output pipe open, so tee never saw EOF
# and the script hung instead of reporting. pgrep is on macOS and on any Linux
# with procps; without it, the parent alone is signalled as before.
function cn1_kill_tree {
  [ -z "$1" ] && return 0
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do
    cn1_kill_tree "$child"
  done
  kill -TERM "$1" 2>/dev/null || true
}

# Runs ./mvnw exactly as before, with the output still on your terminal, and
# reports how it ended.
function cn1_mvnw {
  local target="${CMD:-unknown}" os java start log code
  os="$(cn1_os)"
  java="$(cn1_java_major)"
  start="$(date +%s)"
  cn1_event --data-urlencode "step=launch" --data-urlencode "target=$target" \
    --data-urlencode "os=$os" --data-urlencode "java=$java" &
  log="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/cn1-build-$$.log")"
  # Ctrl+C or a kill while Maven runs must still report how the run ended: a
  # developer who gave up on a hung download or a sign-in that never came
  # otherwise looks like one whose run never finished. The Maven pipeline runs
  # in the BACKGROUND and the script waits for it, because bash defers a trap
  # until a foreground command returns -- a `kill` aimed at this script alone
  # would otherwise wait for a hung Maven forever. The trap stops Maven itself
  # (its pid is recorded from inside the pipeline), waits for tee to flush, then
  # reports and cleans up. tee drains every line Maven wrote before it exits, so
  # nothing at the end of the output (the failure summary) is lost. stdin is
  # passed through explicitly: a background job's stdin is /dev/null otherwise.
  local pipe_pid pidfile="$log.pid"
  trap 'cn1_kill_tree "$(cat "$pidfile" 2>/dev/null)"; wait "$pipe_pid" 2>/dev/null; \
    cn1_event --data-urlencode "step=exit" --data-urlencode "target=$target" \
    --data-urlencode "os=$os" --data-urlencode "java=$java" --data-urlencode "exit=130" \
    --data-urlencode "reason=interrupted" --data-urlencode "secs=$(( $(date +%s) - start ))"; \
    rm -f "$log" "$pidfile"; trap - INT TERM; exit 130' INT TERM
  set +e
  set -o pipefail
  { ./mvnw "$@" <&0 2>&1 & echo $! > "$pidfile"; wait $! 2>/dev/null; } | tee "$log" &
  pipe_pid=$!
  wait "$pipe_pid"
  code=$?
  set +o pipefail
  set -e
  rm -f "$pidfile"
  trap - INT TERM
  cn1_event --data-urlencode "step=exit" --data-urlencode "target=$target" \
    --data-urlencode "os=$os" --data-urlencode "java=$java" --data-urlencode "exit=$code" \
    --data-urlencode "reason=$(cn1_reason "$code" "$log")" \
    --data-urlencode "secs=$(( $(date +%s) - start ))"
  rm -f "$log"
  return "$code"
}

function mac_desktop {

  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=javase" "-Dcodename1.buildTarget=mac-os-x-desktop" "-U" "-e"
}
function mac_native {

  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=ios" "-Dcodename1.buildTarget=mac-os-x-native" "-U" "-e"
}
function mac_catalyst {

  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=ios" "-Dcodename1.buildTarget=mac-catalyst" "-U" "-e"
}
function windows_desktop {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=javase" "-Dcodename1.buildTarget=windows-desktop" "-U" "-e"
}
function windows_device {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=win" "-Dcodename1.buildTarget=windows-device" "-U" "-e"
}
function linux_device {

  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=linux" "-Dcodename1.buildTarget=linux-device" "-U" "-e"
}
function javascript {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=javascript" "-Dcodename1.buildTarget=javascript" "-U" "-e"
}
function android {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=android" "-Dcodename1.buildTarget=android-device" "-U" "-e"
}
function xcode {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=ios" "-Dcodename1.buildTarget=ios-source" "-U" "-e"
}
function ios_source {
  "xcode" 
}
function android_source {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=android" "-Dcodename1.buildTarget=android-source" "-U" "-e"
}
function ios {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=ios" "-Dcodename1.buildTarget=ios-device" "-U" "-e"
}
function ios_release {
  
  "$MVNW" "package" "-DskipTests" "-Dcodename1.platform=ios" "-Dcodename1.buildTarget=ios-device-release" "-U" "-e"
}
function jar {
  
  "$MVNW" "-Pexecutable-jar" "package" "-Dcodename1.platform=javase" "-DskipTests" "-U" "-e"
}
function help {
  "echo" "-e" "build.sh [COMMAND]"
  "echo" "-e" "Local Build Commands:"
  "echo" "-e" "  The following commands will build the app locally (i.e. does NOT use the Codename One build server)"
  "echo" "-e" ""
  "echo" "-e" "  jar"
  "echo" "-e" "    Builds app as desktop app executable jar file to javase/target directory"
  "echo" "-e" "  android_source"
  "echo" "-e" "    Generates an android gradle project that can be opened in Android studio"
  "echo" "-e" "    *Requires android development tools installed."
  "echo" "-e" "    *Requires ANDROID_HOME environment variable"
  "echo" "-e" "    *Requires either GRADLE_HOME environment variable, or for gradle to be in PATH"
  "echo" "-e" "  ios_source"
  "echo" "-e" "    Generates an Xcode Project that you can open and build using Apple's development tools"
  "echo" "-e" "    *Requires a Mac with Xcode installed"
  "echo" "-e" ""
  "echo" "-e" "Build Server Commands:"
  "echo" "-e" "  The following commands will build the app using the Codename One build server, and require"
  "echo" "-e" "  a Codename One account.  See https://www.codenameone.com"
  "echo" "-e" ""
  "echo" "-e" "  ios"
  "echo" "-e" "    Builds iOS app."
  "echo" "-e" "  ios_release"
  "echo" "-e" "    Builds iOS app for submission to Apple appstore."
  "echo" "-e" "  android"
  "echo" "-e" "    Builds android app."
  "echo" "-e" "  mac_desktop"
  "echo" "-e" "    Builds Mac OS desktop app."
  "echo" "-e" "    *Mac OS Desktop builds are a Pro user feature."
  "echo" "-e" "  mac_native"
  "echo" "-e" "    Builds a native Mac app (no JVM)."
  "echo" "-e" "  mac_catalyst"
  "echo" "-e" "    Builds the legacy Mac Catalyst app."
  "echo" "-e" "  windows_desktop"
  "echo" "-e" "    Builds Windows desktop app."
  "echo" "-e" "    *Windows Desktop builds are a Pro user feature."
  "echo" "-e" "  windows_device"
  "echo" "-e" "    Builds a native Windows app (no JVM)."
  "echo" "-e" "  linux_device"
  "echo" "-e" "    Builds a native Linux app (ELF, no JVM)."
  "echo" "-e" "  javascript"
  "echo" "-e" "    Builds as a web app."
}
function settings {
  
  "$MVNW" "cn1:settings" "-U" "-e"
}
CMD="$1"

# No argument is what a first-time developer actually runs, and it has to be
# the cloud build. It used to build a local jar: that never contacts the build
# server, never signs in, exits 0 and prints BUILD SUCCESS, so someone who
# followed the onboarding checklist was told they had succeeded while the
# server saw nothing at all. In production 18 of 18 developers who downloaded
# this starter reached no sign-in handshake.
if [ "$CMD" == "" ]; then
  echo "Building your first CLOUD build (javascript). A browser will open for sign-in."
  echo "For a local jar instead, run ./build.sh jar -- see ./build.sh help for every target."
  CMD="javascript"
fi
"$CMD"
