#!/usr/bin/env bash
# Show installer banner on first login
if [[ -d /root/debian-install ]] && [[ -z "${_INSTALLER_SHOWN:-}" ]]; then
  export _INSTALLER_SHOWN=1
  printf '\n'
  printf '\033[1;36m  ===  Custom Debian Server Installer  ===\033[0m\n'
  printf '\n'
  printf '  Run:  \033[1mbash /root/debian-install/install.sh\033[0m\n'
  printf '  Help: \033[1mbash /root/debian-install/install.sh --help\033[0m\n'
  printf '\n'
fi
