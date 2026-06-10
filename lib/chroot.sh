#!/usr/bin/env bash
# lib/chroot.sh — Chroot wrapper for running scripts inside the new system

# Copy the installer into the chroot and run a script there.
# Usage: run_in_chroot <script> [commands...]
# Example: run_in_chroot lib/configure.sh configure_system
# Example: run_in_chroot profiles/server.sh   (self-executing scripts)
run_in_chroot() {
  local script="$1"
  shift
  local extra_cmds=("$@")
  local chroot_installer="/root/debian-install"

  # Copy installer tree into chroot
  if [[ ! -d "${MOUNT_POINT}${chroot_installer}" ]]; then
    log_debug "Copying installer to ${MOUNT_POINT}${chroot_installer}"
    cp -a "$INSTALLER_DIR" "${MOUNT_POINT}${chroot_installer}"
  fi

  # Copy bundled dotfiles into chroot if available (custom ISO)
  local bundled_dotfiles="/root/dotfiles"
  if [[ -d "$bundled_dotfiles" && ! -d "${MOUNT_POINT}/root/dotfiles" ]]; then
    log_debug "Copying bundled dotfiles to ${MOUNT_POINT}/root/dotfiles"
    cp -a "$bundled_dotfiles" "${MOUNT_POINT}/root/dotfiles"
  fi

  # Build optional extra command lines
  local extra=""
  if [[ ${#extra_cmds[@]} -gt 0 ]]; then
    local cmd
    for cmd in "${extra_cmds[@]}"; do
      extra="${extra}${cmd}"$'\n'
    done
  fi

  # Write the wrapper that sources everything and runs the target script.
  # Every value is emitted with printf %q so a value containing spaces or shell
  # metacharacters cannot break out of (or inject into) the generated script.
  local wrapper_file="${MOUNT_POINT}${chroot_installer}/.chroot-wrapper.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n\n' 'set -euo pipefail'

    printf 'export INSTALLER_DIR=%q\n' "$chroot_installer"
    printf 'export LOG_FILE=%q\n' "$LOG_FILE"
    printf 'export HOSTNAME=%q\n' "$HOSTNAME"
    printf 'export USERNAME=%q\n' "$USERNAME"
    printf 'export TIMEZONE=%q\n' "$TIMEZONE"
    printf 'export LOCALE=%q\n' "$LOCALE"
    printf 'export KEYMAP=%q\n' "$KEYMAP"
    printf 'export BOOTLOADER=%q\n' "$BOOTLOADER"
    printf 'export FS_TYPE=%q\n' "$FS_TYPE"
    printf 'export SWAP_SIZE=%q\n' "$SWAP_SIZE"
    printf 'export ENABLE_DOCKER=%q\n' "$ENABLE_DOCKER"
    printf 'export DEBIAN_RELEASE=%q\n' "$DEBIAN_RELEASE"
    printf 'export MOUNT_POINT=%q\n' ""
    printf 'export PART_EFI=%q\n' "${PART_EFI:-}"
    printf 'export PART_SWAP=%q\n' "${PART_SWAP:-}"
    printf 'export PART_ROOT=%q\n' "${PART_ROOT:-}"
    printf 'export DOTFILES_REPO=%q\n' "${DOTFILES_REPO:-}"
    printf 'export DOTFILES_DEST=%q\n' "${DOTFILES_DEST:-}"
    printf 'export AUTO_MODE=%q\n' "${AUTO_MODE:-0}"
    printf 'export MIRROR_COUNTRY=%q\n' "${MIRROR_COUNTRY:-}"
    printf 'export PROFILE=%q\n' "server"
    printf 'export DEBUG=%q\n' "${DEBUG:-0}"
    printf 'export DEBIAN_FRONTEND=%q\n' "noninteractive"

    printf '\n%s\n' '# Source libraries'
    printf 'source %q\n' "${chroot_installer}/lib/log.sh"
    printf 'source %q\n' "${chroot_installer}/lib/ui.sh"
    printf 'source %q\n' "${chroot_installer}/lib/packages.sh"
    printf 'source %q\n' "${chroot_installer}/lib/services.sh"

    printf '\n%s\n' '# Source the target script (loads functions or executes top-level code)'
    printf 'source %q\n' "${chroot_installer}/${script}"

    printf '\n%s\n' '# Run any extra commands passed as arguments'
    printf '%s' "$extra"
  } > "$wrapper_file"
  chmod +x "$wrapper_file"

  log_debug "Entering chroot to run: $script $extra"
  chroot "$MOUNT_POINT" /usr/bin/bash "${chroot_installer}/.chroot-wrapper.sh"
}

# Mount essential virtual filesystems for chroot
mount_chroot_filesystems() {
  mount --bind /dev "${MOUNT_POINT}/dev"
  mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
  mount -t proc proc "${MOUNT_POINT}/proc"
  mount -t sysfs sysfs "${MOUNT_POINT}/sys"
  mount -t efivarfs efivarfs "${MOUNT_POINT}/sys/firmware/efi/efivars" 2>/dev/null || true

  # Copy resolv.conf for DNS inside chroot
  cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"
}

# Unmount chroot virtual filesystems
umount_chroot_filesystems() {
  umount "${MOUNT_POINT}/sys/firmware/efi/efivars" 2>/dev/null || true
  umount "${MOUNT_POINT}/sys"
  umount "${MOUNT_POINT}/proc"
  umount "${MOUNT_POINT}/dev/pts"
  umount "${MOUNT_POINT}/dev"
}

# Cleanup the installer copy from the chroot
cleanup_chroot() {
  # Safety net: remove password file if configure_users failed to delete it
  local pass_file="${MOUNT_POINT}/root/.install-passwords"
  if [[ -f "$pass_file" ]]; then
    log_warn "Password file still exists — removing it now."
    rm -f "$pass_file"
  fi

  local chroot_installer="${MOUNT_POINT}/root/debian-install"
  if [[ -d "$chroot_installer" ]]; then
    log_debug "Cleaning up installer copy from chroot"
    rm -rf "$chroot_installer"
  fi

  local chroot_dotfiles="${MOUNT_POINT}/root/dotfiles"
  if [[ -d "$chroot_dotfiles" ]]; then
    log_debug "Cleaning up bundled dotfiles from chroot"
    rm -rf "$chroot_dotfiles"
  fi
}
