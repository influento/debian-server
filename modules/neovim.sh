#!/usr/bin/env bash
# modules/neovim.sh — Install Neovim from GitHub binary release
# Uses the 'stable' tag so it always gets the latest stable version.

NEOVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz"
NEOVIM_INSTALL_DIR="/opt/nvim"

log_info "Installing Neovim from GitHub release..."

# Download
local_tarball="/tmp/nvim-linux-x86_64.tar.gz"
run_logged "Downloading Neovim" \
  curl -fsSL -o "$local_tarball" "$NEOVIM_URL"

# Extract to /opt/nvim (remove previous install if upgrading)
if [[ -d "$NEOVIM_INSTALL_DIR" ]]; then
  rm -rf "$NEOVIM_INSTALL_DIR"
fi

mkdir -p "$NEOVIM_INSTALL_DIR"
tar -xzf "$local_tarball" --strip-components=1 -C "$NEOVIM_INSTALL_DIR"
rm -f "$local_tarball"

# Symlink to PATH
ln -sf "${NEOVIM_INSTALL_DIR}/bin/nvim" /usr/local/bin/nvim

# Set as default editor via update-alternatives
update-alternatives --install /usr/bin/editor editor /usr/local/bin/nvim 60

log_info "Neovim installed: $(${NEOVIM_INSTALL_DIR}/bin/nvim --version | head -1)"
