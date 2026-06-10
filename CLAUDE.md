# Debian Server Installer

## Overview

Modular bash-based Debian server installer. Boots from a custom live ISO, runs
debootstrap, and produces a minimal server with SSH, nftables, fail2ban, Docker CE,
and dotfiles (zsh + oh-my-zsh + neovim + tmux via external dotfiles repo).

See @docs/TODO.md for the roadmap and @docs/ARCHITECTURE.md for structure.

## Current Status

**VM-tested** — installer runs end-to-end in QEMU/KVM and Hyper-V (Trixie, UEFI).
Pending: final verification on physical hardware (mini PC).

## Commands

```bash
# Lint
shellcheck -x install.sh lib/*.sh profiles/*.sh modules/*.sh iso/build.sh

# Build ISO (uses Docker volume cache for fast rebuilds)
docker build -t debian-iso-builder iso/
docker run --rm --privileged -v "$(pwd)":/build -v debian-iso-cache:/cache debian-iso-builder
# Output: iso/out/debian-server-custom-YYYY.MM.DD-amd64.iso

# Create QEMU/KVM test VM (Linux) — headless by default
./tests/linux/create-vm.sh              # headless, SSH only
./tests/linux/create-vm.sh --display    # with GTK window
./tests/linux/create-vm.sh --keep       # reuse existing disk (skip reinstall)

# Create Hyper-V test VM (elevated PowerShell)
.\tests\windows\create-vm.ps1

# Run installer (from live ISO — launcher auto-starts on login)
bash /root/debian-install/start.sh
```

## Test VM (QEMU/KVM)

The test VM uses UEFI (OVMF), VirtIO disk/network, and forwards SSH:

- **SSH port**: `2223` → guest port 22
- **Live ISO login**: `ssh -p 2223 root@localhost` (password: `root`)
- **Installed system**: `ssh -p 2223 testuser@localhost` (password: `test`)
- **Serial console**: available on the launching terminal (Ctrl-A c for QEMU monitor)
- **Test config**: `tests/vm-server.conf` (user: `testuser`, disk: `/dev/vda`, swap: 2G)

The script auto-cleans previous VMs and kills stale QEMU processes on launch.

## What Gets Installed

Packages are in `packages/base.list` and `packages/server.list`. Key components:
kernel, firmware, microcode, build-essential, sudo, NetworkManager, systemd-resolved,
zsh, neovim, GRUB, openssh-server, nftables, fail2ban, Docker CE (official repo),
btop, tmux, rsync, fzf, ripgrep, bat, eza, fd-find, zoxide, shellcheck,
starship, fastfetch, nodejs, npm.

## What Gets Configured

- **Disk**: GPT — EFI (1G) + Swap (8G) + Root (rest, ext4). No `/home` split.
- **System**: UTC, en_US.UTF-8, GRUB UEFI, initramfs-tools, systemd-resolved
- **SSH**: hardened config in `/etc/ssh/sshd_config.d/10-hardened.conf`
- **Firewall**: nftables — drop incoming, allow SSH/ICMP/established, allow outgoing
  (Docker `-p` published ports bypass this — see docs/TODO.md "Security Hardening")
- **Docker**: Docker CE from official repo, user added to docker group
- **User**: root + non-root user with sudo group (NOPASSWD), zsh shell
- **Dotfiles**: deployed from `DOTFILES_REPO` to `~/dev/infra/dotfiles`, runs `install.sh --profile server`

## File Organization

```
start.sh                Interactive launcher (install / test / shell menu)
install.sh              Entry point
config.sh               Default variables
lib/                    Core libraries (log, ui, checks, disk, bootstrap, configure, chroot, packages, services)
profiles/base.sh        Dotfiles deployment
profiles/server.sh      Server profile orchestrator
modules/                SSH, firewall, Docker
packages/               Package lists (base.list, server.list)
iso/                    Custom ISO builder (Dockerfile, build.sh, overlay/)
tests/                  VM testing (linux/, windows/, vm-server.conf)
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
- Before every commit/push, audit the staged diff for sensitive information leaks:
  usernames, passwords, API keys, tokens, private IPs, email addresses, or any
  data that should not appear in a public repository. Flag any findings to the user
  before proceeding

## Debian Version

Target: **Trixie** (Debian 13) — set via `DEBIAN_RELEASE` in `config.sh`.
Update when new stable releases.
