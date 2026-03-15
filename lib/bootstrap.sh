#!/usr/bin/env bash
# lib/bootstrap.sh — Debootstrap and base system installation
# Replaces pacstrap.sh from the Arch installer.

bootstrap_base_system() {
  log_section "Base System Installation"

  if ! command -v debootstrap &>/dev/null; then
    die "debootstrap not found. Install it first: apt-get install -y debootstrap"
  fi

  # Determine mirror URL (country mirror with CDN fallback)
  local mirror_url="http://deb.debian.org/debian"
  if [[ -n "${MIRROR_COUNTRY:-}" ]]; then
    local cc_lower
    cc_lower="$(printf '%s' "$MIRROR_COUNTRY" | tr '[:upper:]' '[:lower:]')"
    local country_mirror="http://ftp.${cc_lower}.debian.org/debian"
    if curl -sf --max-time 5 -o /dev/null "${country_mirror}/dists/${DEBIAN_RELEASE}/Release" 2>/dev/null; then
      mirror_url="$country_mirror"
      log_info "Using country mirror: $mirror_url"
    else
      log_warn "Country mirror unreachable, using CDN: $mirror_url"
    fi
  fi

  log_info "Bootstrapping Debian ${DEBIAN_RELEASE} to ${MOUNT_POINT}..."

  run_logged "Running debootstrap" \
    debootstrap \
      --arch=amd64 \
      --components=main,contrib,non-free-firmware \
      "${DEBIAN_RELEASE}" \
      "${MOUNT_POINT}" \
      "$mirror_url"

  log_info "Generating fstab..."
  generate_fstab

  log_info "fstab generated."
}

# Generate /etc/fstab from current mounts
generate_fstab() {
  local fstab_file="${MOUNT_POINT}/etc/fstab"

  cat > "$fstab_file" <<'HEADER'
# /etc/fstab: static file system information.
# <file system>  <mount point>  <type>  <options>  <dump>  <pass>
HEADER

  # Root partition
  local root_uuid
  root_uuid="$(blkid -s UUID -o value "$PART_ROOT")"
  printf 'UUID=%s  /         %s  defaults,errors=remount-ro  0  1\n' \
    "$root_uuid" "$FS_TYPE" >> "$fstab_file"

  # EFI partition
  local efi_uuid
  efi_uuid="$(blkid -s UUID -o value "$PART_EFI")"
  printf 'UUID=%s  /boot/efi  vfat  umask=0077  0  2\n' \
    "$efi_uuid" >> "$fstab_file"

  # Swap partition
  local swap_uuid
  swap_uuid="$(blkid -s UUID -o value "$PART_SWAP")"
  printf 'UUID=%s  none      swap  sw  0  0\n' \
    "$swap_uuid" >> "$fstab_file"
}
