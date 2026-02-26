#!/usr/bin/env bash
# modules/docker.sh — Docker CE setup for Debian
# Uses official Docker repository (not Debian's older docker.io package).

# --- Helper: write Docker apt source for a given release codename ---
write_docker_source() {
  local release="$1"
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${release} stable
EOF
}

log_info "Setting up Docker CE repository..."

# Install prerequisites for Docker repo
run_logged "Installing Docker repo prerequisites" \
  apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
gpg_tmp="/tmp/docker-gpg.key"
run_logged "Downloading Docker GPG key" \
  curl -fsSL -o "$gpg_tmp" https://download.docker.com/linux/debian/gpg
gpg --dearmor -o /etc/apt/keyrings/docker.gpg < "$gpg_tmp"
chmod a+r /etc/apt/keyrings/docker.gpg
rm -f "$gpg_tmp"

# Add Docker repository for the configured release
write_docker_source "$DEBIAN_RELEASE"

# Update apt — fall back to bookworm if the configured release has no packages
if ! run_logged "Updating package lists (Docker repo)" apt-get update; then
  log_warn "Docker repo unavailable for ${DEBIAN_RELEASE}, falling back to bookworm..."
  write_docker_source "bookworm"
  run_logged "Updating package lists (Docker repo — bookworm)" apt-get update
fi

# Install Docker CE packages
run_logged "Installing Docker CE" \
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add the non-root user to the docker group
if id "$USERNAME" &>/dev/null; then
  usermod -aG docker "$USERNAME"
  log_info "User $USERNAME added to docker group."
fi

log_info "Docker CE installed and configured."
