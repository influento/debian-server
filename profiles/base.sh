#!/usr/bin/env bash
# profiles/base.sh — Shared base setup called by all profiles
# This runs inside chroot. Libraries are already sourced by the chroot wrapper.

run_base_profile() {
  log_section "Base Profile Setup"

  deploy_dotfiles

  log_info "Base profile setup complete."
}

# Deploy dotfiles from bundled copy (custom ISO) or git clone (standard flow).
# Skips if DOTFILES_REPO is not set.
deploy_dotfiles() {
  if [[ -z "${DOTFILES_REPO:-}" ]]; then
    log_warn "DOTFILES_REPO not set — skipping dotfiles deployment."
    return 0
  fi

  local dest="${DOTFILES_DEST:-/home/${USERNAME}/.dotfiles}"

  log_info "Deploying dotfiles to ${dest}..."

  if [[ -d "/root/dotfiles" ]]; then
    # Custom ISO flow: bundled dotfiles already present
    log_info "Using bundled dotfiles from /root/dotfiles"
    cp -a "/root/dotfiles" "$dest"
  else
    # Standard flow: clone from remote
    log_info "Cloning dotfiles from ${DOTFILES_REPO}..."
    git clone "$DOTFILES_REPO" "$dest"
  fi

  # Ensure the dotfiles repo remote points to the SSH URL for push/pull.
  # The bundled copy (or HTTPS clone) may have a different remote.
  if [[ -d "${dest}/.git" ]]; then
    local current_remote
    current_remote="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
    if [[ "$current_remote" != "$DOTFILES_REPO" ]]; then
      log_info "Updating git remote to ${DOTFILES_REPO}"
      git -C "$dest" remote set-url origin "$DOTFILES_REPO"
    fi
  fi

  # Fix ownership (we're running as root in chroot)
  chown -R "${USERNAME}:${USERNAME}" "$dest"

  # Run the dotfiles installer if present
  if [[ -f "${dest}/install.sh" ]]; then
    log_info "Running dotfiles install.sh --profile ${PROFILE:-server} --user ${USERNAME}..."
    sudo -u "$USERNAME" bash "${dest}/install.sh" --profile "${PROFILE:-server}" --user "$USERNAME"
  else
    log_warn "No install.sh found in dotfiles — skipping automated setup."
  fi

  log_info "Dotfiles deployed to ${dest}."
}
