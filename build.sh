#!/usr/bin/env bash
# Build TRMNL firmware v1.8.18 with keys.patch applied, and optionally flash it.
#
#   ./build.sh                 build only
#   ./build.sh COM3            build and flash over USB (plug the board in first)
#
# Needs git, Python and PlatformIO (pip install platformio). The firmware tree is
# cloned next to this repo (../trmnl-firmware-keys): ESP-IDF builds break on long
# Windows paths, so keep it short.
set -euo pipefail

TAG="${TRMNL_FW_TAG:-v1.8.18}"
ENV_NAME="TRMNL_7inch5_OG_DIY_Kit"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${TRMNL_FW_DIR:-$HERE/../trmnl-firmware-keys}" # reset hard on every run: not your own clone
PORT="${1:-}"

if [ ! -d "$SRC/.git" ]; then
  git clone --branch "$TAG" https://github.com/usetrmnl/trmnl-firmware "$SRC"
fi

cd "$SRC"
git checkout -q "$TAG"
git reset -q --hard
git clean -fdq # files an older patch added (build output is git-ignored and stays)
git apply "$HERE/keys.patch"

# Optional built-in Wi-Fi: wifi.local (git-ignored) with two lines,
#   WIFI_SSID=name
#   WIFI_PASSWORD=secret
# The device uses it whenever it has no saved network.
if [ -f "$HERE/wifi.local" ]; then
  WIFI_SSID="$(sed -n 's/^WIFI_SSID=//p' "$HERE/wifi.local" | tr -d '\r')"
  WIFI_PASSWORD="$(sed -n 's/^WIFI_PASSWORD=//p' "$HERE/wifi.local" | tr -d '\r')"
  export PLATFORMIO_BUILD_FLAGS="-DWIFI_DEFAULT_SSID=\\\"$WIFI_SSID\\\" -DWIFI_DEFAULT_PASSWORD=\\\"$WIFI_PASSWORD\\\""
  echo "Built-in Wi-Fi: $WIFI_SSID"
fi

python -m platformio run -e "$ENV_NAME"

if [ -n "$PORT" ]; then
  # The board is only on USB while awake; wait for it rather than fail.
  if ! python -m serial.tools.list_ports | grep -qw "^$PORT"; then
    echo "Waiting for $PORT - press KEY1 or KEY2 briefly to wake the board (not a long KEY3 press)..."
    for _ in $(seq 1 600); do
      python -m serial.tools.list_ports | grep -qw "^$PORT" && break
      sleep 1
    done
  fi
  python -m platformio run -e "$ENV_NAME" -t upload --upload-port "$PORT"
fi
