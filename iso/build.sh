#!/usr/bin/env bash
# iso/build.sh — Builds a custom Debian live ISO with the installer pre-loaded.
# Runs inside the Docker container. Do not run directly on the host.
set -euo pipefail

# --- Configuration ---

BUILD_DIR="/build"
WORK_DIR="/tmp/live-build"
CACHE_DIR="/cache"
OUTPUT_DIR="${BUILD_DIR}/iso/out"
OVERLAY_DIR="${BUILD_DIR}/iso/overlay"

ISO_LABEL="debian-server-custom"
DOTFILES_HTTPS="https://github.com/influento/dotfiles.git"

# --- Logging ---

log_info() {
  printf '\033[1;32m==> \033[0m%s\n' "$1"
}

log_detail() {
  printf '    \033[0;37m%s\033[0m\n' "$1"
}

log_error() {
  printf '\033[1;31m==> ERROR: \033[0m%s\n' "$1" >&2
}

# --- Preflight checks ---

if [[ ! -f "${BUILD_DIR}/install.sh" ]]; then
  log_error "Installer repo not found at $BUILD_DIR. Mount the repo root to /build."
  exit 1
fi

# --- Start build ---

log_info "Building custom Debian live ISO"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
cd "$WORK_DIR"

# --- Step 1: Configure live-build ---

log_info "Configuring live-build..."
lb config \
  --distribution trixie \
  --archive-areas "main contrib non-free-firmware" \
  --debian-installer none \
  --memtest none \
  --bootappend-live "boot=live components username=root" \
  --iso-application "$ISO_LABEL" \
  --iso-volume "$ISO_LABEL"

# --- Step 1.5: Restore cache from previous build ---

if [[ -d "${CACHE_DIR}/bootstrap" || -d "${CACHE_DIR}/packages" ]]; then
  log_info "Restoring package cache from previous build..."
  mkdir -p cache
  cp -a "${CACHE_DIR}"/* cache/ 2>/dev/null || true
  log_detail "Cache restored — build will skip most downloads"
else
  log_info "No previous cache found — full download required"
fi

# --- Step 2: Add packages for the live environment ---

log_info "Adding live environment packages..."

# Packages needed to run the installer from the live ISO
live_packages=(
  debootstrap
  git
  parted
  gdisk
  dosfstools
  e2fsprogs
  btrfs-progs
  efibootmgr
  grub-efi-amd64-bin
  curl
  ca-certificates
  gnupg
  sudo
  neovim
  less
)

for pkg in "${live_packages[@]}"; do
  echo "$pkg" >> config/package-lists/installer.list.chroot
  log_detail "$pkg"
done

# Append extra packages from overlay
if [[ -f "${OVERLAY_DIR}/packages-extra.txt" ]]; then
  log_info "Adding extra packages from overlay..."
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line// /}"
    [[ -z "$line" ]] && continue
    log_detail "$line"
    echo "$line" >> config/package-lists/installer.list.chroot
  done < "${OVERLAY_DIR}/packages-extra.txt"
fi

# --- Step 3: Inject installer scripts ---

log_info "Injecting installer scripts into ISO..."
local_dest="config/includes.chroot/root/debian-install"
mkdir -p "$local_dest"

# Use tar to copy with exclusions (avoids rsync dependency)
tar -C "$BUILD_DIR" \
  --exclude='.git' \
  --exclude='iso/out' \
  --exclude='iso/work' \
  --exclude='tests/iso' \
  --exclude='.claude' \
  -cf - . | tar -C "$local_dest" -xf -

log_detail "Scripts injected to /root/debian-install/"

# --- Step 4: Clone dotfiles ---

log_info "Cloning dotfiles (HTTPS for Docker build)..."
local_dotfiles="config/includes.chroot/root/dotfiles"

if git clone "$DOTFILES_HTTPS" "$local_dotfiles"; then
  log_detail "Dotfiles cloned to /root/dotfiles/"
else
  log_error "Failed to clone dotfiles — continuing without them"
fi

# --- Step 5: Apply overlay files ---

log_info "Applying overlay files..."
if [[ -d "${OVERLAY_DIR}/includes.chroot" ]]; then
  cp -r "${OVERLAY_DIR}/includes.chroot/"* config/includes.chroot/
  log_detail "Overlay files applied"
fi

# Ensure installer is executable
chmod +x "config/includes.chroot/root/debian-install/install.sh"

# --- Step 6: Build the ISO ---

log_info "Running live-build (this will take several minutes)..."
lb build

# --- Step 6.5: Save cache for next build ---

if [[ -d cache ]]; then
  log_info "Saving package cache for future builds..."
  mkdir -p "$CACHE_DIR"
  rm -rf "${CACHE_DIR:?}"/*
  cp -a cache/* "$CACHE_DIR"/ 2>/dev/null || true
  log_detail "Cache saved to $CACHE_DIR"
fi

# --- Step 7: Rename ISO and generate checksum ---

log_info "Generating output..."

iso_date="$(date '+%Y.%m.%d')"
iso_name="${ISO_LABEL}-${iso_date}-amd64.iso"

# live-build outputs to live-image-amd64.hybrid.iso (or similar)
built_iso=""
for f in live-image-*.iso; do
  [[ -f "$f" ]] && built_iso="$f" && break
done

if [[ -z "$built_iso" ]]; then
  log_error "No ISO file produced by live-build!"
  exit 1
fi

mv "$built_iso" "${OUTPUT_DIR}/${iso_name}"

cd "$OUTPUT_DIR"
sha256sum "$iso_name" > sha256sums.txt
iso_size="$(du -h "$iso_name" | cut -f1)"

log_info "Build complete!"
log_detail "ISO: ${OUTPUT_DIR}/${iso_name}"
log_detail "Size: ${iso_size}"
log_detail "SHA256: $(cut -d' ' -f1 sha256sums.txt)"

# --- Cleanup ---

rm -rf "$WORK_DIR"
log_info "Done."
