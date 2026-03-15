#!/usr/bin/env bash
# install.sh — Main entry point for the Debian server installer
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Resolve installer directory
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source defaults
# shellcheck source=config.sh
source "${INSTALLER_DIR}/config.sh"

# Source libraries
# shellcheck source=lib/log.sh
source "${INSTALLER_DIR}/lib/log.sh"
source "${INSTALLER_DIR}/lib/ui.sh"
source "${INSTALLER_DIR}/lib/checks.sh"
source "${INSTALLER_DIR}/lib/disk.sh"
source "${INSTALLER_DIR}/lib/packages.sh"
source "${INSTALLER_DIR}/lib/bootstrap.sh"
source "${INSTALLER_DIR}/lib/chroot.sh"

# --- CLI argument parsing ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --disk DEVICE         Target disk (e.g. /dev/nvme0n1, /dev/sda)
  --hostname NAME       System hostname
  --user USERNAME       Non-root username (prompted if not set)
  --timezone ZONE       Timezone (default: UTC)
  --locale LOCALE       System locale (default: en_US.UTF-8)
  --keymap MAP          Console keymap (default: us)
  --fs-type TYPE        Root filesystem: ext4 | btrfs (default: ext4)
  --swap SIZE           Swap size (default: 8G)
  --release CODENAME    Debian release codename (default: trixie)
  --dotfiles URL        Dotfiles git repo URL
  --mirror-country CC   2-letter country code for mirrors (e.g. US, DE)
  --config FILE         Source a config file with variable overrides
  --auto                Unattended mode (skip confirmations, use PASSWORD var)
  --dry-run             Show what would be done without making changes
  --debug               Enable debug output
  --help                Show this help message
EOF
  exit 0
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)        TARGET_DISK="$2"; shift 2 ;;
    --hostname)    HOSTNAME="$2"; shift 2 ;;
    --user)        USERNAME="$2"; shift 2 ;;
    --timezone)    TIMEZONE="$2"; shift 2 ;;
    --locale)      LOCALE="$2"; shift 2 ;;
    --keymap)      KEYMAP="$2"; shift 2 ;;
    --fs-type)     FS_TYPE="$2"; shift 2 ;;
    --swap)        SWAP_SIZE="$2"; shift 2 ;;
    --release)     DEBIAN_RELEASE="$2"; shift 2 ;;
    --dotfiles)    DOTFILES_REPO="$2"; shift 2 ;;
    --mirror-country) MIRROR_COUNTRY="$2"; shift 2 ;;
    --config)      # shellcheck source=/dev/null
                   source "$2"; shift 2 ;;
    --auto)        AUTO_MODE=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --debug)       DEBUG=1; shift ;;
    --help)        usage ;;
    *)             die "Unknown option: $1. Use --help for usage." ;;
  esac
done

# --- Initialize logging ---

mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
log_info "Debian Server Installer started"
log_info "Log file: $LOG_FILE"

# --- Preflight ---

run_preflight_checks

# --- Detect geo location (mirror country) ---

if [[ -z "$MIRROR_COUNTRY" ]]; then
  log_info "Detecting location..."
  _geo_json="$(curl -sf --max-time 5 "https://ipapi.co/json/" 2>/dev/null)" || _geo_json=""

  # Fallback to ip-api.com
  if [[ -z "$_geo_json" ]]; then
    _geo_json="$(curl -sf --max-time 5 "http://ip-api.com/json/?fields=countryCode" 2>/dev/null)" || _geo_json=""
  fi

  _GEO_COUNTRY=""
  if [[ -n "$_geo_json" ]]; then
    # ipapi.co uses "country_code", ip-api.com uses "countryCode" — try both
    _GEO_COUNTRY="$(printf '%s' "$_geo_json" | sed -n 's/.*"country_code": *"\([^"]*\)".*/\1/p')"
    [[ -z "$_GEO_COUNTRY" ]] && _GEO_COUNTRY="$(printf '%s' "$_geo_json" | sed -n 's/.*"countryCode": *"\([^"]*\)".*/\1/p')"
  fi

  # Validate country code (exactly 2 uppercase letters)
  if [[ ! "${_GEO_COUNTRY:-}" =~ ^[A-Z]{2}$ ]]; then
    _GEO_COUNTRY=""
  fi

  if [[ -n "$_GEO_COUNTRY" ]]; then
    MIRROR_COUNTRY="$_GEO_COUNTRY"
    log_info "Detected mirror country: $MIRROR_COUNTRY"
  else
    log_warn "Could not detect location."
  fi
fi

# --- Gather configuration interactively ---

log_section "Configuration"

# Username
if [[ -z "$USERNAME" ]]; then
  if [[ "$AUTO_MODE" -eq 1 ]]; then
    die "AUTO_MODE requires USERNAME to be set via --user or config file."
  fi
  USERNAME=$(prompt_input "Enter non-root username" "")
  while [[ -z "$USERNAME" ]]; do
    log_warn "Username cannot be empty."
    USERNAME=$(prompt_input "Enter non-root username" "")
  done
fi
log_info "Username: $USERNAME"

# Hostname
if [[ -z "$HOSTNAME" ]]; then
  if [[ "$AUTO_MODE" -eq 1 ]]; then
    local_suffix="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  else
    local_suffix=$(prompt_input "Enter hostname suffix (e.g. home, lab, prod)" "")
    if [[ -z "$local_suffix" ]]; then
      local_suffix="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
  fi
  HOSTNAME="${USERNAME}-server-${local_suffix}"
fi
log_info "Hostname: $HOSTNAME"

log_info "Timezone: $TIMEZONE"
log_info "Debian release: $DEBIAN_RELEASE"

# Disk selection (interactive if not set)
if [[ -z "$TARGET_DISK" ]]; then
  if [[ "$AUTO_MODE" -eq 1 ]]; then
    die "AUTO_MODE requires TARGET_DISK to be set via --disk or config file."
  fi
  TARGET_DISK=$(select_disk)
fi
log_info "Target disk: $TARGET_DISK"

# Passwords
if [[ -n "${PASSWORD:-}" ]]; then
  # PASSWORD set via config/env (e.g. test runs) — use for both
  _ROOT_PASS="$PASSWORD"
  _USER_PASS="$PASSWORD"
elif [[ "$AUTO_MODE" -eq 1 ]]; then
  die "AUTO_MODE requires PASSWORD to be set via config file or environment."
else
  _ROOT_PASS=$(prompt_password "Root password")
  _USER_PASS=$(prompt_password "Password for $USERNAME")
fi

# --- Show summary and confirm ---

print_summary \
  "Hostname=$HOSTNAME" \
  "Username=$USERNAME" \
  "Timezone=$TIMEZONE" \
  "Locale=$LOCALE" \
  "Keymap=$KEYMAP" \
  "Filesystem=$FS_TYPE" \
  "Swap=${SWAP_SIZE}" \
  "Bootloader=$BOOTLOADER" \
  "Debian=${DEBIAN_RELEASE}" \
  "Disk=${TARGET_DISK}" \
  "Dotfiles=${DOTFILES_REPO:-<none>}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  _ROOT_PASS="" _USER_PASS=""
  unset _ROOT_PASS _USER_PASS
  log_info "Dry run — exiting before making changes."
  exit 0
fi

if ! confirm "Proceed with installation?"; then
  _ROOT_PASS="" _USER_PASS=""
  unset _ROOT_PASS _USER_PASS
  die "Aborted by user."
fi

# ===================================================================
#  Phase 1: Disk + Base System (live ISO environment)
# ===================================================================

setup_disk
bootstrap_base_system

# ===================================================================
#  Phase 2: System Configuration (inside chroot)
# ===================================================================

mount_chroot_filesystems

# Pass passwords into chroot via temp file (mode 0600, deleted after use)
_PASS_FILE="${MOUNT_POINT}/root/.install-passwords"
printf '%s\n%s\n' "$_ROOT_PASS" "$_USER_PASS" > "$_PASS_FILE"
chmod 600 "$_PASS_FILE"
_ROOT_PASS="" _USER_PASS=""
unset _ROOT_PASS _USER_PASS

run_in_chroot "lib/configure.sh" "configure_system" "enable_base_services"

# ===================================================================
#  Phase 3: Profile Execution (inside chroot)
# ===================================================================

run_in_chroot "profiles/server.sh"

# ===================================================================
#  Post-chroot fixups (must happen outside chroot)
# ===================================================================

# Point resolv.conf to systemd-resolved stub resolver.
# This can't be done inside chroot because the host's resolv.conf may be
# bind-mounted for DNS resolution during the chroot session.
log_info "Configuring resolv.conf symlink..."
rm -f "${MOUNT_POINT}/etc/resolv.conf"
ln -s ../run/systemd/resolve/stub-resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

# ===================================================================
#  Cleanup and Reboot
# ===================================================================

log_section "Installation Complete"

umount_chroot_filesystems

cleanup_chroot

log_info "Installation finished successfully!"
log_info "Log saved to: ${MOUNT_POINT}${LOG_FILE}"

# Copy log into the installed system
cp "$LOG_FILE" "${MOUNT_POINT}${LOG_FILE}" 2>/dev/null || true

log_info "Rebooting in 5 seconds..."
sleep 5
swapoff -a 2>/dev/null || true
umount -R "$MOUNT_POINT" 2>/dev/null || true
reboot
