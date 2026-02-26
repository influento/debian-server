#!/usr/bin/env bash
# lib/disk.sh — Disk detection, partitioning, formatting, and mounting
# UEFI only. Server layout: EFI(1G) + Swap(8G) + Root(rest)

# ---------- helpers ----------

# Determine the partition device prefix (/dev/sda → /dev/sda, /dev/nvme0n1 → /dev/nvme0n1p).
part_prefix() {
  local disk="$1"
  if [[ "$disk" == *nvme* || "$disk" == *mmcblk* ]]; then
    printf '%sp' "$disk"
  else
    printf '%s' "$disk"
  fi
}

# ---------- main entry ----------

setup_disk() {
  log_section "Disk Setup"

  # Select disk if not set
  if [[ -z "$TARGET_DISK" ]]; then
    TARGET_DISK=$(select_disk)
  fi
  log_info "Target disk: $TARGET_DISK"

  # Swap size
  if [[ -z "$SWAP_SIZE" ]]; then
    SWAP_SIZE="8G"
    log_info "Swap size (server default): $SWAP_SIZE"
  fi

  # Safety confirmation
  log_warn "ALL DATA ON $TARGET_DISK WILL BE DESTROYED."
  confirm "Proceed with partitioning $TARGET_DISK?" || die "Aborted by user."

  partition_disk
  format_partitions
  mount_partitions
}

# ---------- partitioning ----------

partition_disk() {
  local prefix
  prefix=$(part_prefix "$TARGET_DISK")

  # Server: EFI(1) + Swap(2) + Root/rest(3)
  run_logged "Wiping partition table" sgdisk --zap-all "$TARGET_DISK"

  run_logged "Creating EFI partition (${EFI_SIZE})" \
    sgdisk -n 1:0:+"${EFI_SIZE}" -t 1:ef00 -c 1:"EFI" "$TARGET_DISK"

  run_logged "Creating swap partition (${SWAP_SIZE})" \
    sgdisk -n 2:0:+"${SWAP_SIZE}" -t 2:8200 -c 2:"Swap" "$TARGET_DISK"

  run_logged "Creating root partition (remaining space)" \
    sgdisk -n 3:0:0 -t 3:8300 -c 3:"Root" "$TARGET_DISK"

  PART_EFI="${prefix}1"
  PART_SWAP="${prefix}2"
  PART_ROOT="${prefix}3"

  run_logged "Reloading partition table" partprobe "$TARGET_DISK"
  log_info "Partitions: EFI=$PART_EFI SWAP=$PART_SWAP ROOT=$PART_ROOT"
}

# ---------- formatting ----------

format_partitions() {
  log_info "Formatting partitions..."

  # Unmount any auto-mounted partitions (live environments may auto-mount new partitions)
  umount "$PART_EFI" 2>/dev/null || true
  umount "$PART_SWAP" 2>/dev/null || true
  umount "$PART_ROOT" 2>/dev/null || true

  run_logged "Formatting EFI (FAT32)" mkfs.fat -F 32 "$PART_EFI"
  run_logged "Formatting swap" mkswap "$PART_SWAP"

  case "$FS_TYPE" in
    ext4)
      run_logged "Formatting root (ext4)" mkfs.ext4 -F "$PART_ROOT"
      ;;
    btrfs)
      run_logged "Formatting root (btrfs)" mkfs.btrfs -f "$PART_ROOT"
      ;;
    *)
      die "Unsupported filesystem: $FS_TYPE"
      ;;
  esac
}

# ---------- mounting ----------

mount_partitions() {
  log_info "Mounting partitions..."

  run_logged "Mounting root" mount "$PART_ROOT" "$MOUNT_POINT"

  # GRUB expects EFI at /boot/efi (not /boot like systemd-boot)
  mkdir -p "${MOUNT_POINT}/boot/efi"
  run_logged "Mounting EFI at /boot/efi" mount "$PART_EFI" "${MOUNT_POINT}/boot/efi"

  run_logged "Activating swap" swapon "$PART_SWAP"

  log_info "All partitions mounted."
}
