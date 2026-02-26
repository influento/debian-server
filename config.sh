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

# --- System ---
HOSTNAME="${HOSTNAME:-}"                      # prompted if empty; pattern: {username}-server-{suffix}
USERNAME="${USERNAME:-}"                       # non-root user (prompted if empty)
TIMEZONE="${TIMEZONE:-UTC}"                   # UTC for servers
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"

# --- Boot ---
BOOTLOADER="${BOOTLOADER:-grub}"             # GRUB (UEFI only)

# --- Software ---
EDITOR="${EDITOR:-nvim}"                      # default editor for visudo, git, etc.
ENABLE_DOCKER="${ENABLE_DOCKER:-true}"        # install Docker CE

# --- Dotfiles ---
DOTFILES_REPO="${DOTFILES_REPO:-}"             # git URL (empty = skip dotfiles)
DOTFILES_DEST="${DOTFILES_DEST:-}"             # auto-set to /home/$USERNAME/.dotfiles

# --- Paths (internal, don't override) ---
# shellcheck disable=SC2034 # INSTALLER_DIR is used by install.sh and chroot wrapper
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/debian-install.log}"
MOUNT_POINT="${MOUNT_POINT:-/mnt}"
