#!/bin/bash

set -euo pipefail

watchio_script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
watchio_repository_root="$(cd "${watchio_script_directory}/.." && pwd)"
watchio_install_root="${WATCHIO_INSTALL_DIR:-${HOME}/Applications}"
watchio_destination="${watchio_install_root}/Watchio.app"
watchio_derived_data="${WATCHIO_DERIVED_DATA:-${watchio_repository_root}/.build/Install}"
watchio_development_team="${WATCHIO_DEVELOPMENT_TEAM:-}"
watchio_stage=""
watchio_stopped_pids=()

watchio_fail() {
  printf 'Watchio install failed: %s\n' "$1" >&2
  exit 1
}

watchio_cleanup() {
  if [[ -n "${watchio_stage}" && "${watchio_stage}" == "${watchio_install_root}"/.watchio-install.* ]]; then
    /bin/rm -rf "${watchio_stage}"
  fi
}

trap watchio_cleanup EXIT

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || watchio_fail "macOS is required."
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || watchio_fail "an Apple Silicon Mac is required."
/usr/bin/xcodebuild -version >/dev/null 2>&1 || watchio_fail "install Xcode and select it with xcode-select first."

watchio_macos_version="$(/usr/bin/sw_vers -productVersion)"
watchio_macos_major="${watchio_macos_version%%.*}"
[[ "${watchio_macos_major}" =~ ^[0-9]+$ && "${watchio_macos_major}" -ge 14 ]] \
  || watchio_fail "macOS 14 or newer is required."

printf 'Building Watchio Release for Apple Silicon…\n'
watchio_build_arguments=(
  -quiet
  -project "${watchio_repository_root}/Watchio.xcodeproj"
  -scheme Watchio
  -destination "platform=macOS,arch=arm64"
  -derivedDataPath "${watchio_derived_data}"
  -configuration Release
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES
)

if [[ -n "${watchio_development_team}" ]]; then
  watchio_build_arguments+=(
    "DEVELOPMENT_TEAM=${watchio_development_team}"
    CODE_SIGN_STYLE=Automatic
    -allowProvisioningUpdates
  )
else
  watchio_build_arguments+=(CODE_SIGN_IDENTITY=-)
fi

/usr/bin/xcodebuild "${watchio_build_arguments[@]}" build

watchio_product="${watchio_derived_data}/Build/Products/Release/Watchio.app"
[[ -x "${watchio_product}/Contents/MacOS/Watchio" ]] \
  || watchio_fail "the Release app was not produced at ${watchio_product}."
[[ -d "${watchio_product}/Contents/PlugIns/WatchioWidget.appex" ]] \
  || watchio_fail "the widget extension is missing from the Release app."

/bin/mkdir -p "${watchio_install_root}"
watchio_stage="$(/usr/bin/mktemp -d "${watchio_install_root}/.watchio-install.XXXXXX")"
/usr/bin/ditto "${watchio_product}" "${watchio_stage}/Watchio.app"
/usr/bin/codesign --verify --deep --strict "${watchio_stage}/Watchio.app"

watchio_running_pids="$(/usr/bin/pgrep -x Watchio || true)"
if [[ -n "${watchio_running_pids}" ]]; then
  while IFS= read -r watchio_pid; do
    watchio_command="$(/bin/ps -p "${watchio_pid}" -o command= 2>/dev/null || true)"
    if [[ "${watchio_command}" == "${watchio_destination}/Contents/MacOS/Watchio" \
      || ("${WATCHIO_SKIP_OPEN:-0}" != "1" && "${watchio_command}" == */Watchio.app/Contents/MacOS/Watchio) ]]; then
      /bin/kill "${watchio_pid}"
      watchio_stopped_pids+=("${watchio_pid}")
    fi
  done <<<"${watchio_running_pids}"
fi

for watchio_pid in "${watchio_stopped_pids[@]}"; do
  for _ in {1..30}; do
    if ! /bin/kill -0 "${watchio_pid}" 2>/dev/null; then
      break
    fi
    /bin/sleep 0.1
  done
  if /bin/kill -0 "${watchio_pid}" 2>/dev/null; then
    watchio_fail "quit the existing Watchio app and run the installer again."
  fi
done

watchio_previous="${watchio_stage}/Previous.app"
if [[ -e "${watchio_destination}" ]]; then
  /bin/mv "${watchio_destination}" "${watchio_previous}"
fi

if ! /bin/mv "${watchio_stage}/Watchio.app" "${watchio_destination}"; then
  if [[ -e "${watchio_previous}" ]]; then
    /bin/mv "${watchio_previous}" "${watchio_destination}"
  fi
  watchio_fail "could not move Watchio into ${watchio_install_root}."
fi

printf 'Installed Watchio at %s\n' "${watchio_destination}"

if [[ "${WATCHIO_SKIP_OPEN:-0}" != "1" ]]; then
  /usr/bin/open "${watchio_destination}" \
    || watchio_fail "the app was installed, but macOS could not open it."
  watchio_started=0
  for _ in {1..30}; do
    watchio_running_pids="$(/usr/bin/pgrep -x Watchio || true)"
    if [[ -n "${watchio_running_pids}" ]]; then
      while IFS= read -r watchio_pid; do
        watchio_command="$(/bin/ps -p "${watchio_pid}" -o command= 2>/dev/null || true)"
        if [[ "${watchio_command}" == "${watchio_destination}/Contents/MacOS/Watchio" ]]; then
          watchio_started=1
          break
        fi
      done <<<"${watchio_running_pids}"
    fi
    [[ "${watchio_started}" == "1" ]] && break
    /bin/sleep 0.1
  done
  [[ "${watchio_started}" == "1" ]] \
    || watchio_fail "the app was installed, but it did not stay running."
  printf 'Watchio is running. Look for w: in the menu bar.\n'
fi
