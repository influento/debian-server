#!/usr/bin/env bash
# start.sh — Interactive launcher for the Debian server installer
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
readonly _B='\033[1m'
readonly _C='\033[1;36m'
readonly _Y='\033[1;33m'
readonly _R='\033[0m'

printf '\n'
printf '%b  ===  Debian Server Installer  ===%b\n' "$_C" "$_R"
printf '\n'
printf '  %b1)%b Install          — full interactive install\n' "$_B" "$_R"
printf '  %b2)%b Test (VM)        — pre-filled config, smaller swap\n' "$_B" "$_R"
printf '  %b3)%b Test dry-run     — pre-filled config, no changes\n' "$_B" "$_R"
printf '  %b4)%b Test (auto)      — pre-filled config, unattended\n' "$_B" "$_R"
printf '  %b5)%b Custom           — pass your own flags\n' "$_B" "$_R"
printf '\n'

while true; do
  printf '%b::%b Choose an option [1-5]: ' "$_Y" "$_R"
  read -r choice
  case "$choice" in
    1)
      exec bash "${INSTALLER_DIR}/install.sh"
      ;;
    2)
      exec bash "${INSTALLER_DIR}/install.sh" --config "${INSTALLER_DIR}/tests/vm-server.conf"
      ;;
    3)
      exec bash "${INSTALLER_DIR}/install.sh" --config "${INSTALLER_DIR}/tests/vm-server.conf" --dry-run
      ;;
    4)
      exec bash "${INSTALLER_DIR}/install.sh" --config "${INSTALLER_DIR}/tests/vm-server.conf" --auto
      ;;
    5)
      printf '\n  Enter flags (e.g. --disk /dev/sda --hostname mybox):\n'
      printf '%b::%b ' "$_Y" "$_R"
      read -r flags
      # shellcheck disable=SC2086
      exec bash "${INSTALLER_DIR}/install.sh" $flags
      ;;
    *)
      printf '  %bInvalid choice. Try again.%b\n' "$_Y" "$_R"
      ;;
  esac
done
