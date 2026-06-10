#!/usr/bin/env bash
# config.sh — Default configuration variables
# Override via CLI flags, config file (--config), or environment variables.

# --- Debian ---
DEBIAN_RELEASE="${DEBIAN_RELEASE:-trixie}"   # Debian stable codename (update when new stable releases)

# --- Disk ---
TARGET_DISK="${TARGET_DISK:-}"                # /dev/sdX or /dev/nvmeXnY (prompted if empty)
FS_TYPE="${FS_TYPE:-ext4}"                    # ext4 | btrfs
EFI_SIZE="${EFI_SIZE:-1G}"                    # EFI system partition size
ROOT_SIZE="${ROOT_SIZE:-}"                    # Server: rest of disk (empty = use all remaining)
SWAP_SIZE="${SWAP_SIZE:-8G}"                  # Server default: 8G

# --- Install mode ---
AUTO_MODE="${AUTO_MODE:-0}"                   # 1 = unattended mode (skip confirmations)
PASSWORD="${PASSWORD:-}"                      # used in --auto mode for both root + user

# --- System ---
HOSTNAME=""                                      # always prompt (shell sets HOSTNAME automatically)
USERNAME="${USERNAME:-}"                       # non-root user (prompted if empty)
TIMEZONE="${TIMEZONE:-UTC}"                   # UTC for servers
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"

# --- Boot ---
BOOTLOADER="${BOOTLOADER:-grub}"             # GRUB (UEFI only)

# --- Software ---
ENABLE_DOCKER="${ENABLE_DOCKER:-true}"        # install Docker CE

# --- Mirrors ---
MIRROR_COUNTRY="${MIRROR_COUNTRY:-}"          # 2-letter country code for mirrors (auto-detected)

# --- Dotfiles ---
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/influento/dotfiles.git}"
DOTFILES_DEST="${DOTFILES_DEST:-}"             # auto-set to /home/$USERNAME/dev/infra/dotfiles

# --- Paths (internal, don't override) ---
# shellcheck disable=SC2034 # INSTALLER_DIR is used by install.sh and chroot wrapper
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/debian-install.log}"
MOUNT_POINT="${MOUNT_POINT:-/mnt}"
