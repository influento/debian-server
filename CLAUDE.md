# Debian Server Installer

## Overview

Modular bash-based Debian server installer. Boots from a custom live ISO, runs
debootstrap, and produces a minimal server with SSH, nftables, fail2ban, Docker CE,
and dotfiles (zsh + oh-my-zsh + neovim + tmux via external dotfiles repo).

See @docs/TODO.md for the roadmap and @docs/ARCHITECTURE.md for structure.

## Current Status

**VM-tested** — installer runs end-to-end in Hyper-V (Trixie, Gen 2 UEFI).
Pending: final verification on physical hardware.

## Commands

```bash
# Lint
shellcheck -x install.sh lib/*.sh profiles/*.sh modules/*.sh iso/build.sh

# Build ISO (uses Docker volume cache for fast rebuilds)
docker build -t debian-iso-builder iso/
docker run --rm --privileged -v "$(pwd)":/build -v debian-iso-cache:/cache debian-iso-builder
# Output: iso/out/debian-server-custom-YYYY.MM.DD-amd64.iso

# Create Hyper-V test VM (elevated PowerShell)
.\tests\create-vm.ps1

# Run installer (from live ISO)
bash /root/debian-install/install.sh --config /root/debian-install/tests/vm-server.conf
```

## What Gets Installed

Packages are in `packages/base.list` and `packages/server.list`. Key components:
kernel, firmware, microcode, build-essential, sudo, NetworkManager, systemd-resolved,
zsh, neovim, GRUB, openssh-server, nftables, fail2ban, Docker CE (official repo),
htop, tmux, rsync.

## What Gets Configured

- **Disk**: GPT — EFI (1G) + Swap (8G) + Root (rest, ext4). No `/home` split.
- **System**: UTC, en_US.UTF-8, GRUB UEFI, initramfs-tools, systemd-resolved
- **SSH**: hardened config in `/etc/ssh/sshd_config.d/10-hardened.conf`
- **Firewall**: nftables — drop incoming, allow SSH/ICMP/established, allow outgoing
- **Docker**: Docker CE from official repo, user added to docker group
- **User**: root + non-root user with sudo group, zsh shell
- **Dotfiles**: deployed from `DOTFILES_REPO` to `~/.dotfiles`, runs `install.sh --profile server`

## File Organization

```
install.sh              Entry point
config.sh               Default variables
lib/                    Core libraries (log, ui, checks, disk, bootstrap, configure, chroot, packages, services)
profiles/base.sh        Dotfiles deployment
profiles/server.sh      Server profile orchestrator
modules/                SSH, firewall, Docker
packages/               Package lists (base.list, server.list)
iso/                    Custom ISO builder (Dockerfile, build.sh, overlay/)
tests/                  VM config (vm-server.conf, create-vm.ps1)
docs/                   TODO.md, ARCHITECTURE.md
```

## Code Conventions

- `#!/usr/bin/env bash` + `set -euo pipefail`
- shellcheck-clean (`shellcheck -x`)
- 2-space indent, `snake_case` functions, `UPPER_SNAKE` config vars
- `local` for function-scoped variables, quote all expansions
- `[[ ]]` conditionals, `$(command)` substitution
- Logging via `lib/log.sh` — never print directly

## Key Patterns

- Package lists in `packages/` — not hardcoded in scripts
- Modules are self-contained (install packages, deploy config, enable services)
- Profiles compose modules — no package/config logic in profiles
- Everything after debootstrap runs inside chroot via `lib/chroot.sh`
- Config precedence: CLI flags > config file > `config.sh` defaults
- Docker packages from Docker's official Debian repo (not docker.io)

## Git

- Do NOT add `Co-Authored-By` trailers to commits

## Debian Version

Target: **Trixie** (Debian 13) — set via `DEBIAN_RELEASE` in `config.sh`.
Update when new stable releases.
