#!/usr/bin/env bash
# lib/configure.sh — System configuration (runs inside chroot)

configure_system() {
  log_section "System Configuration"

  configure_apt
  install_packages_from_list "${INSTALLER_DIR}/packages/base.list"
  configure_timezone
  configure_locale
  configure_hostname
  configure_dns
  configure_initramfs
  configure_bootloader
  configure_users
  configure_sudo
}

configure_apt() {
  log_info "Configuring apt..."

  cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${DEBIAN_RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security ${DEBIAN_RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${DEBIAN_RELEASE}-updates main contrib non-free-firmware
EOF

  run_logged "Updating package lists" apt-get update
}

configure_timezone() {
  log_info "Setting timezone to $TIMEZONE"
  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  # hwclock is not available inside chroot — skip if missing
  if command -v hwclock &>/dev/null; then
    run_logged "Syncing hardware clock" hwclock --systohc
  fi
}

configure_locale() {
  log_info "Configuring locale: $LOCALE"

  # Uncomment the desired locale
  sed -i "s/^# ${LOCALE}/${LOCALE}/" /etc/locale.gen

  # Always ensure en_US.UTF-8 is available as fallback
  sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen

  run_logged "Generating locales" locale-gen

  echo "LANG=${LOCALE}" > /etc/default/locale

  cat > /etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="${KEYMAP}"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
}

configure_hostname() {
  log_info "Setting hostname: $HOSTNAME"

  echo "$HOSTNAME" > /etc/hostname

  cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
}

configure_dns() {
  log_info "Configuring systemd-resolved for DNS..."

  # Enable systemd-resolved service
  run_logged "Enabling systemd-resolved" systemctl enable systemd-resolved

  # NOTE: resolv.conf symlink is created post-chroot in install.sh because
  # chroot may bind-mount the host's /etc/resolv.conf for DNS during chroot.

  log_info "DNS configured (systemd-resolved + NetworkManager)."
}

configure_initramfs() {
  log_info "Configuring initramfs..."

  run_logged "Generating initramfs" update-initramfs -u -k all
}

configure_bootloader() {
  log_info "Installing bootloader: $BOOTLOADER"

  case "$BOOTLOADER" in
    grub)
      run_logged "Installing GRUB to EFI" \
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian

      run_logged "Generating GRUB configuration" update-grub

      log_info "GRUB installed (UEFI mode)."
      ;;
    *)
      die "Unsupported bootloader: $BOOTLOADER (only grub is supported)"
      ;;
  esac
}

configure_users() {
  log_section "User Setup"

  # Read passwords from temp file created by install.sh
  local pass_file="/root/.install-passwords"
  if [[ ! -f "$pass_file" ]]; then
    die "Password file not found — expected $pass_file from install.sh."
  fi

  local root_pass user_pass
  { read -r root_pass; read -r user_pass; } < "$pass_file"
  rm -f "$pass_file"

  # Root password
  echo "root:${root_pass}" | chpasswd
  root_pass=""
  log_info "Root password set."

  # Non-root user
  log_info "Creating user: $USERNAME"
  useradd -m -G sudo -s /usr/bin/zsh "$USERNAME"

  echo "${USERNAME}:${user_pass}" | chpasswd
  user_pass=""
  log_info "User $USERNAME created."
}

configure_sudo() {
  log_info "Configuring sudo..."

  # On Debian, the sudo group is used instead of wheel
  # NOPASSWD so interactive installs and package scripts never prompt
  mkdir -p /etc/sudoers.d
  echo '%sudo ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/01-sudo-nopasswd
  chmod 440 /etc/sudoers.d/01-sudo-nopasswd

  # Set default editor for visudo
  mkdir -p /etc/sudoers.d
  echo "Defaults editor=/usr/bin/${EDITOR}" > /etc/sudoers.d/00-editor
  chmod 440 /etc/sudoers.d/00-editor
}
