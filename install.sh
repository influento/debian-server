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
  --config FILE         Source a config file with variable overrides
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
    --config)      # shellcheck source=/dev/null
                   source "$2"; shift 2 ;;
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

# --- Gather configuration interactively ---

log_section "Configuration"

# Username
if [[ -z "$USERNAME" ]]; then
  USERNAME=$(prompt_input "Enter non-root username" "")
  while [[ -z "$USERNAME" ]]; do
    log_warn "Username cannot be empty."
    USERNAME=$(prompt_input "Enter non-root username" "")
  done
fi
log_info "Username: $USERNAME"

# Hostname
if [[ -z "$HOSTNAME" ]]; then
  local_suffix=$(prompt_input "Enter hostname suffix (e.g. home, lab, prod)" "")
  if [[ -z "$local_suffix" ]]; then
    local_suffix="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  fi
  HOSTNAME="${USERNAME}-server-${local_suffix}"
fi
log_info "Hostname: $HOSTNAME"

log_info "Timezone: $TIMEZONE"
log_info "Debian release: $DEBIAN_RELEASE"

# Disk selection (interactive if not set)
if [[ -z "$TARGET_DISK" ]]; then
  TARGET_DISK=$(select_disk)
fi
log_info "Target disk: $TARGET_DISK"

# Passwords
_ROOT_PASS=$(prompt_password "Root password")
_USER_PASS=$(prompt_password "Password for $USERNAME")

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
