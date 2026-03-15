#!/usr/bin/env bash
# Creates a QEMU/KVM VM for testing the Debian server installer.
#
# Creates a UEFI VM with:
# - OVMF firmware (UEFI, no Secure Boot)
# - Configurable RAM, CPUs, and disk size
# - Debian ISO attached as CD-ROM
# - User-mode networking (internet access, no root required)
# - VirtIO disk and network for performance
# - Headless by default (interact via SSH), --display for GTK window
#
# Usage: ./tests/linux/create-vm.sh [options]
#
# Options:
#   --name NAME         VM name (default: debiantest)
#   --memory MB         RAM in MB (default: 4096)
#   --cpus N            Number of CPUs (default: 2)
#   --disk-size GB      Disk size in GB (default: 60)
#   --iso PATH          Path to Debian ISO (default: auto-detect)
#   --display           Show GTK window (default: headless)
#   --no-launch         Create the VM disk and print the command, don't launch
#   --keep              Keep existing VM disk (default: clean up and recreate)
#   --help              Show this help

set -euo pipefail

# --- Defaults ---

VM_NAME="debiantest"
MEMORY_MB=4096
CPUS=2
DISK_SIZE_GB=60
ISO_PATH=""
LAUNCH=true
KEEP_EXISTING=false
DISPLAY_MODE="none"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$TESTS_DIR")"
VM_DIR="${TESTS_DIR}/vm"

OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       VM_NAME="$2"; shift 2 ;;
    --memory)     MEMORY_MB="$2"; shift 2 ;;
    --cpus)       CPUS="$2"; shift 2 ;;
    --disk-size)  DISK_SIZE_GB="$2"; shift 2 ;;
    --iso)        ISO_PATH="$2"; shift 2 ;;
    --display)    DISPLAY_MODE="gtk"; shift ;;
    --no-launch)  LAUNCH=false; shift ;;
    --keep)       KEEP_EXISTING=true; shift ;;
    --help)
      sed -n '2,/^$/s/^# \?//p' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# --- Output helpers ---

print_step() {
  printf '\n\033[36m==>\033[0m %s\n' "$1"
}

print_ok() {
  printf '    \033[32m[OK]\033[0m %s\n' "$1"
}

print_fail() {
  printf '    \033[31m[FAIL]\033[0m %s\n' "$1"
}

print_detail() {
  printf '    \033[90m%s\033[0m\n' "$1"
}

# --- Check dependencies ---

print_step "Checking dependencies..."

for cmd in qemu-system-x86_64 qemu-img; do
  if command -v "$cmd" &>/dev/null; then
    print_ok "$cmd found"
  else
    print_fail "$cmd not found. Install qemu-full."
    exit 1
  fi
done

if [[ ! -f "$OVMF_CODE" ]]; then
  print_fail "OVMF firmware not found: $OVMF_CODE"
  print_detail "Install edk2-ovmf package."
  exit 1
fi
print_ok "OVMF firmware found"

if [[ -e /dev/kvm ]]; then
  print_ok "KVM available (/dev/kvm)"
elif lsmod 2>/dev/null | grep -q kvm; then
  print_ok "KVM module loaded"
else
  print_fail "KVM not available. Check your BIOS virtualization settings or install kvm."
  exit 1
fi

# --- Auto-detect ISO ---

if [[ -z "$ISO_PATH" ]]; then
  # Prefer custom ISO from iso/out/, fall back to tests/iso/
  custom_iso_dir="${REPO_DIR}/iso/out"
  stock_iso_dir="${TESTS_DIR}/iso"

  iso_found=""

  # Check custom ISOs first
  if [[ -d "$custom_iso_dir" ]]; then
    iso_found=$(find "$custom_iso_dir" -name "debian-server-custom-*.iso" -type f 2>/dev/null | sort -r | head -1)
    if [[ -n "$iso_found" ]]; then
      print_detail "Found custom ISO in iso/out/"
    fi
  fi

  # Fall back to stock ISOs
  if [[ -z "$iso_found" && -d "$stock_iso_dir" ]]; then
    iso_found=$(find "$stock_iso_dir" -name "debian-*.iso" -type f 2>/dev/null | sort -r | head -1)
  fi

  if [[ -z "$iso_found" ]]; then
    print_fail "No Debian ISO found."
    print_detail "Build a custom ISO:      docker build -t debian-iso-builder iso/ && docker run --rm --privileged -v \"\$(pwd)\":/build -v debian-iso-cache:/cache debian-iso-builder"
    print_detail "Or download a stock ISO:  ./tests/linux/download-iso.sh"
    exit 1
  fi

  ISO_PATH="$iso_found"
fi

if [[ ! -f "$ISO_PATH" ]]; then
  print_fail "ISO not found: $ISO_PATH"
  exit 1
fi

# --- Create VM directory and disk ---

mkdir -p "$VM_DIR"

disk_path="${VM_DIR}/${VM_NAME}.qcow2"
vars_path="${VM_DIR}/${VM_NAME}_VARS.fd"

printf '\n'
printf '\033[36mQEMU/KVM VM Creator - Debian Server Installer Testing\033[0m\n'
printf '\033[90m=====================================================\033[0m\n'

print_step "Configuration"
print_detail "VM Name:     $VM_NAME"
print_detail "Memory:      $MEMORY_MB MB"
print_detail "CPUs:        $CPUS"
print_detail "Disk:        $DISK_SIZE_GB GB (qcow2) -> $disk_path"
print_detail "ISO:         $ISO_PATH"
print_detail "OVMF:        $OVMF_CODE"

# Clean up existing VM files (unless --keep)
if [[ -f "$disk_path" || -f "$vars_path" ]]; then
  if [[ "$KEEP_EXISTING" == "true" ]]; then
    print_step "Reusing existing VM disk..."
    print_ok "Disk: $disk_path"
    if [[ ! -f "$vars_path" ]]; then
      cp "$OVMF_VARS" "$vars_path"
      print_ok "UEFI vars created: $vars_path"
    else
      print_ok "UEFI vars: $vars_path"
    fi
  else
    print_step "Cleaning up previous VM '$VM_NAME'..."
    [[ -f "$disk_path" ]] && rm "$disk_path" && print_ok "Removed old disk"
    [[ -f "$vars_path" ]] && rm "$vars_path" && print_ok "Removed old UEFI vars"
  fi
fi

if [[ ! -f "$disk_path" ]]; then
  print_step "Creating VM disk..."
  qemu-img create -f qcow2 "$disk_path" "${DISK_SIZE_GB}G"
  print_ok "Disk created: $disk_path"
fi

# Copy OVMF vars (writable copy for this VM's UEFI settings)
if [[ ! -f "$vars_path" ]]; then
  cp "$OVMF_VARS" "$vars_path"
  print_ok "UEFI vars: $vars_path"
fi

# --- Kill any existing VM with the same name ---

existing_pid=$(pgrep -f "qemu-system-x86_64.*-name ${VM_NAME}" || true)
if [[ -n "$existing_pid" ]]; then
  print_step "Stopping existing VM '$VM_NAME' (PID $existing_pid)..."
  kill "$existing_pid" 2>/dev/null || true
  sleep 1
  print_ok "Stopped"
fi

# --- Build QEMU command ---

# shellcheck disable=SC2054
qemu_cmd=(
  qemu-system-x86_64
  -name "$VM_NAME"
  -machine "q35,accel=kvm"
  -cpu host
  -smp "$CPUS"
  -m "$MEMORY_MB"

  # UEFI firmware
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$vars_path"

  # Virtual disk (VirtIO for performance)
  -drive "file=$disk_path,format=qcow2,if=virtio,cache=writeback"

  # CD-ROM with Debian ISO (boot from this first)
  -cdrom "$ISO_PATH"
  -boot d

  # Network (user-mode — internet access, no root required)
  # Port forward: host 2222 → guest 22 (SSH)
  -nic "user,model=virtio-net-pci,hostfwd=tcp::2223-:22"

  # Display (headless by default, --display for GTK)
  -display "$DISPLAY_MODE"
  -vga virtio

  # Serial console — installer output visible in host terminal
  # Ctrl-A c to toggle between serial and QEMU monitor
  -serial mon:stdio
)

# --- Launch or print ---

printf '\n\033[90m=====================================================\033[0m\n'
print_ok "VM '$VM_NAME' is ready."

if [[ "$LAUNCH" == "true" ]]; then
  print_step "Launching VM..."
  print_detail "SSH (live ISO): ssh -p 2223 root@localhost  (password: root)"
  print_detail "SSH (installed): ssh -p 2223 testuser@localhost"
  print_detail "Serial console on this terminal (Ctrl-A c for QEMU monitor)"
  print_detail "Eject ISO: Ctrl-A c, then 'eject ide1-cd0'"
  if [[ "$DISPLAY_MODE" == "none" ]]; then
    print_detail "Relaunch with --display for GTK window if needed"
  fi
  printf '\n'

  exec "${qemu_cmd[@]}"
else
  print_step "Launch command (run this to start the VM):"
  printf '\n'
  printf '%s \\\n' "${qemu_cmd[0]}"
  for (( i=1; i<${#qemu_cmd[@]}; i++ )); do
    if [[ "${qemu_cmd[$i]}" == -* ]]; then
      printf '  %s' "${qemu_cmd[$i]}"
    else
      printf ' %s' "${qemu_cmd[$i]}"
    fi
    if (( i < ${#qemu_cmd[@]} - 1 )); then
      printf ' \\\n'
    fi
  done
  printf '\n\n'
  printf '    # Remove -cdrom and -boot d flags, or eject in the QEMU monitor\n'
  printf '\n'
fi
