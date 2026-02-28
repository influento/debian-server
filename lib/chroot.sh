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

  # Build the wrapper that sources everything and runs the target script
  local wrapper
  wrapper=$(cat <<CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

export INSTALLER_DIR="${chroot_installer}"
export LOG_FILE="${LOG_FILE}"
export HOSTNAME="${HOSTNAME}"
export USERNAME="${USERNAME}"
export TIMEZONE="${TIMEZONE}"
export LOCALE="${LOCALE}"
export KEYMAP="${KEYMAP}"
export BOOTLOADER="${BOOTLOADER}"
export FS_TYPE="${FS_TYPE}"
export SWAP_SIZE="${SWAP_SIZE}"
export EDITOR="${EDITOR}"
export ENABLE_DOCKER="${ENABLE_DOCKER}"
export DEBIAN_RELEASE="${DEBIAN_RELEASE}"
export MOUNT_POINT=""
export PART_EFI="${PART_EFI:-}"
export PART_SWAP="${PART_SWAP:-}"
export PART_ROOT="${PART_ROOT:-}"
export DOTFILES_REPO="${DOTFILES_REPO:-}"
export DOTFILES_DEST="${DOTFILES_DEST:-}"
export AUTO_MODE="${AUTO_MODE:-0}"
export MIRROR_COUNTRY="${MIRROR_COUNTRY:-}"
export PROFILE="server"
export DEBUG="${DEBUG:-0}"

# Source libraries
source "\${INSTALLER_DIR}/lib/log.sh"
source "\${INSTALLER_DIR}/lib/ui.sh"
source "\${INSTALLER_DIR}/lib/packages.sh"
source "\${INSTALLER_DIR}/lib/services.sh"

# Source the target script (loads functions or executes top-level code)
source "\${INSTALLER_DIR}/${script}"

# Run any extra commands passed as arguments
${extra}
CHROOT_EOF
  )

  # Write wrapper to a file and execute it (instead of piping to bash).
  local wrapper_file="${MOUNT_POINT}${chroot_installer}/.chroot-wrapper.sh"
  printf '%s' "$wrapper" > "$wrapper_file"
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
