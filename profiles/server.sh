#!/usr/bin/env bash
# profiles/server.sh — Server profile orchestrator
# Minimal system: SSH, firewall, Docker. No GUI. Runs inside chroot.

source "${INSTALLER_DIR}/profiles/base.sh"
run_base_profile

log_section "Server Profile"

# Install server packages
install_packages_from_list "${INSTALLER_DIR}/packages/server.list"

# Run server modules
source "${INSTALLER_DIR}/modules/ssh.sh"
source "${INSTALLER_DIR}/modules/firewall.sh"
if [[ "${ENABLE_DOCKER}" == "true" ]]; then
  source "${INSTALLER_DIR}/modules/docker.sh"
fi

# Enable server services
local_services=(ssh fail2ban nftables)
if [[ "${ENABLE_DOCKER}" == "true" ]]; then
  local_services+=(docker)
fi
enable_services "${local_services[@]}"

log_info "Server profile complete."
