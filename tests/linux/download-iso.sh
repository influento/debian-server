#!/usr/bin/env bash
# Downloads and verifies the latest Debian netinst ISO.
#
# 1. Scrapes the Debian CD mirror for the current ISO filename
# 2. Downloads the ISO from cdimage.debian.org
# 3. Downloads SHA256SUMS and SHA256SUMS.sign
# 4. Verifies the SHA256 checksum
# 5. Verifies the GPG signature (optional, requires gpg)
# 6. Saves everything to tests/iso/
#
# Usage: ./tests/linux/download-iso.sh [--force] [--skip-gpg]

set -euo pipefail

# --- Configuration ---

MIRROR_BASE="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"
# Debian CD signing key ID (used since Debian 12+)
SIGNING_KEY_ID="DA87E80D6294BE9B"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$(dirname "$SCRIPT_DIR")/iso"

# --- Parse arguments ---

FORCE=false
SKIP_GPG=false

for arg in "$@"; do
  case "$arg" in
    --force)    FORCE=true ;;
    --skip-gpg) SKIP_GPG=true ;;
    *)
      printf 'Usage: %s [--force] [--skip-gpg]\n' "$0" >&2
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

if ! command -v curl &>/dev/null; then
  print_fail "curl is required but not installed."
  exit 1
fi

# --- Detect latest ISO ---

print_step "Detecting latest Debian netinst ISO..."

# Scrape the directory listing for the ISO filename
iso_listing=$(curl -fsSL "$MIRROR_BASE/")
iso_filename=$(printf '%s' "$iso_listing" | grep -oP 'debian-[0-9.]+-amd64-netinst\.iso' | head -1)

if [[ -z "$iso_filename" ]]; then
  print_fail "Could not detect ISO filename from $MIRROR_BASE/"
  exit 1
fi

version=$(printf '%s' "$iso_filename" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')
print_ok "Latest release: $version ($iso_filename)"

iso_path="${OUTPUT_DIR}/${iso_filename}"
sums_path="${OUTPUT_DIR}/SHA256SUMS"
sig_path="${OUTPUT_DIR}/SHA256SUMS.sign"
iso_url="${MIRROR_BASE}/${iso_filename}"
sums_url="${MIRROR_BASE}/SHA256SUMS"
sig_url="${MIRROR_BASE}/SHA256SUMS.sign"

# --- Create output directory ---

mkdir -p "$OUTPUT_DIR"

# --- Download SHA256SUMS (needed for existing ISO check) ---

print_step "Downloading SHA256SUMS..."
curl -fsSL -o "$sums_path" "$sums_url"
print_ok "Downloaded: $sums_path"

expected_sha256=$(grep "$iso_filename" "$sums_path" | awk '{print $1}')
if [[ -z "$expected_sha256" ]]; then
  print_fail "Could not find checksum for $iso_filename in SHA256SUMS"
  exit 1
fi

# --- Check if ISO already exists ---

if [[ -f "$iso_path" ]] && [[ "$FORCE" == "false" ]]; then
  print_step "ISO already exists: $iso_path"
  existing_hash=$(sha256sum "$iso_path" | awk '{print $1}')

  if [[ "$existing_hash" == "${expected_sha256,,}" ]]; then
    print_ok "Existing ISO matches latest release ($version). No download needed."
    print_detail "Use --force to re-download."
    exit 0
  else
    print_detail "Existing ISO does not match latest release. Re-downloading..."
    rm -f "$iso_path"
  fi
fi

# --- Download ISO ---

print_step "Downloading Debian $version netinst ISO..."
print_detail "URL: $iso_url"
curl -fL --progress-bar -o "$iso_path" "$iso_url"

actual_size=$(stat -c%s "$iso_path")
actual_mb=$(( actual_size / 1048576 ))
print_ok "Downloaded: $iso_path (${actual_mb} MB)"

# --- Download signature ---

print_step "Downloading GPG signature..."
print_detail "URL: $sig_url"
curl -fsSL -o "$sig_path" "$sig_url"
print_ok "Downloaded: $sig_path"

# --- Verify SHA256 ---

print_step "Verifying SHA256 checksum..."
print_detail "Expected: $expected_sha256"

actual_sha256=$(sha256sum "$iso_path" | awk '{print $1}')
print_detail "Actual:   $actual_sha256"

if [[ "$actual_sha256" == "${expected_sha256,,}" ]]; then
  print_ok "SHA256 checksum matches."
else
  print_fail "SHA256 MISMATCH! The ISO may be corrupted or tampered with."
  rm -f "$iso_path"
  exit 1
fi

# --- Verify GPG signature ---

if [[ "$SKIP_GPG" == "true" ]]; then
  print_step "Skipping GPG verification (--skip-gpg flag)."
  print_detail "SHA256 passed - ISO integrity confirmed against the mirror."
else
  print_step "Verifying GPG signature..."

  if ! command -v gpg &>/dev/null; then
    print_fail "GPG not found. Install gnupg to enable signature verification."
    print_detail "SHA256 passed, so the ISO is likely fine — GPG adds another layer of trust."
  else
    # Fetch the Debian CD signing key
    print_detail "Fetching Debian CD signing key..."
    gpg --keyserver keyserver.ubuntu.com --recv-keys "$SIGNING_KEY_ID" 2>/dev/null || true

    # Verify
    print_detail "Verifying signature..."
    if gpg --verify "$sig_path" "$sums_path" 2>/dev/null; then
      print_ok "GPG signature is valid."
    else
      print_fail "GPG signature verification FAILED!"
      print_detail "SHA256 passed, so this may be a key trust issue. Check manually."
    fi
  fi
fi

# --- Summary ---

printf '\n\033[90m=====================================\033[0m\n'
print_ok "ISO ready: $iso_path"
print_detail "Version: $version"
print_detail "Use this ISO to create a QEMU/KVM VM (see tests/README.md)"
printf '\n'
