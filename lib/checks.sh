#!/usr/bin/env bash
# lib/checks.sh — Preflight checks before installation

run_preflight_checks() {
  log_section "Preflight Checks"

  check_root
  check_uefi
  check_network
  check_disks
  sync_clock
  apply_live_keymap

  log_info "All preflight checks passed."
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root."
  fi
  log_info "Running as root — OK"
}

check_uefi() {
  if [[ ! -d /sys/firmware/efi/efivars ]]; then
    die "UEFI boot mode not detected. This installer requires UEFI. Disable CSM/Legacy in your firmware settings."
  fi
  log_info "UEFI boot mode detected — OK"
}

check_network() {
  if ! ping -c 1 -W 3 debian.org &>/dev/null; then
    die "No network connectivity. Connect to the internet before running the installer."
  fi
  log_info "Network connectivity — OK"
}

check_disks() {
  local disk_count
  disk_count=$(lsblk -dpno NAME | grep -cE '(sd|nvme|vd)' || true)
  if [[ "$disk_count" -eq 0 ]]; then
    die "No suitable block devices found."
  fi
  log_info "Found $disk_count block device(s) — OK"
}

sync_clock() {
  # Ensure system clock is accurate (prevents TLS/SSL failures during install).
  # timedatectl may not work in all live environments (no systemd-timesyncd).
  log_info "Enabling NTP time sync"
  if timedatectl set-ntp true 2>/dev/null; then
    log_info "System clock synced — OK"
  else
    log_warn "NTP sync unavailable in live environment — skipping (clock may be inaccurate)"
  fi
}

apply_live_keymap() {
  # Apply console keymap in the live environment if non-default
  if [[ "$KEYMAP" != "us" ]]; then
    run_logged "Loading keymap: $KEYMAP" loadkeys "$KEYMAP"
  fi
}
