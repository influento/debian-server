# Architecture

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Boot mode | UEFI only | All modern hardware; no Legacy/MBR path |
| Bootloader | GRUB | Standard Debian, integrated with initramfs-tools |
| Filesystem | ext4 | Battle-tested; btrfs available as option |
| Kernel | linux-image-amd64 | Debian meta-package, tracks latest stable |
| Firewall | nftables | Kernel-native, replaces iptables |
| DNS | systemd-resolved | Integrates with NetworkManager |
| Shell | zsh + oh-my-zsh | Via dotfiles repo |
| Editor | neovim | For visudo, git, etc. |
| Docker | Docker CE (official repo) | Not Debian's older docker.io |
| Bootstrap | debootstrap | Standard Debian bootstrap |
| Initramfs | initramfs-tools | Debian default |

## Directory Structure

```
debian-server/
├── start.sh                     # Interactive launcher (install/test/dry-run menu)
├── install.sh                   # Entry point
├── config.sh                    # Default config variables
├── lib/
│   ├── log.sh                   # Logging (info, warn, error, section, run_logged)
│   ├── ui.sh                    # Prompts, menus, confirmation
│   ├── checks.sh                # Preflight (root, UEFI, network, disks)
│   ├── disk.sh                  # Partitioning, formatting, mounting
│   ├── bootstrap.sh             # Debootstrap + fstab
│   ├── configure.sh             # Timezone, locale, hostname, DNS, users, GRUB
│   ├── packages.sh              # apt-get install from .list files
│   ├── services.sh              # systemctl enable
│   └── chroot.sh                # Chroot wrapper + virtual FS mount/umount
├── profiles/
│   ├── base.sh                  # Dotfiles deployment
│   └── server.sh                # Server profile (modules + services)
├── modules/
│   ├── ssh.sh                   # Hardened sshd config
│   ├── firewall.sh              # nftables ruleset
│   └── docker.sh                # Docker CE repo + install
├── packages/
│   ├── base.list                # Core system packages
│   └── server.list              # Server packages
├── iso/
│   ├── Dockerfile               # Debian container with live-build
│   ├── build.sh                 # ISO build script (Docker volume cache)
│   └── overlay/                 # Extra packages, motd, welcome banner
├── tests/
│   ├── vm-server.conf           # Pre-filled test config
│   └── create-vm.ps1            # Hyper-V VM creation script
└── docs/
    ├── TODO.md
    └── ARCHITECTURE.md
```

## Execution Flow

```
start.sh (auto-launches on ISO boot)
  └── install.sh
        ├── Preflight checks (root, UEFI, network, disks)
        ├── Gather ALL input (username, hostname, disk, passwords)
        ├── Summary + confirm
        ├── Disk setup (GPT: EFI + Swap + Root)
        ├── Debootstrap + fstab
        ├── Write password file → chroot
        ├── [chroot] System config (apt, locale, hostname, DNS, initramfs, GRUB, users)
        ├── [chroot] Server profile (dotfiles, packages, SSH, firewall, Docker)
        ├── Post-chroot fixups (resolv.conf symlink)
        └── Cleanup + auto-reboot
```

Everything after debootstrap runs inside chroot. The `lib/chroot.sh` wrapper copies
the installer and bundled dotfiles into `/mnt`, mounts virtual filesystems, runs
scripts, and cleans up after.

## Configuration Variables

| Variable | Default | Description |
|---|---|---|
| `DEBIAN_RELEASE` | `trixie` | Debian stable codename |
| `TARGET_DISK` | *(interactive)* | Target disk device |
| `HOSTNAME` | *(prompted)* | System hostname |
| `USERNAME` | *(prompted)* | Non-root user |
| `TIMEZONE` | `UTC` | Timezone |
| `LOCALE` | `en_US.UTF-8` | System locale |
| `FS_TYPE` | `ext4` | Root filesystem |
| `SWAP_SIZE` | `8G` | Swap partition size |
| `ENABLE_DOCKER` | `true` | Install Docker CE |
| `DOTFILES_REPO` | *(empty)* | Dotfiles git URL (empty = skip) |
| `DOTFILES_DEST` | *(auto)* | `/home/$USERNAME/.dotfiles` |

Precedence: CLI flags > config file (`--config`) > `config.sh` defaults.

## Custom ISO Builder

```bash
docker build -t debian-iso-builder iso/
docker run --rm --privileged -v "$(pwd)":/build -v debian-iso-cache:/cache debian-iso-builder
```

Produces a Debian live ISO with:
- Installer at `/root/debian-install/`
- Dotfiles at `/root/dotfiles/`
- Root auto-login
- All tools needed to run the installer (debootstrap, gdisk, parted, etc.)

Uses a Docker volume (`debian-iso-cache`) to cache packages between builds.
Output: `iso/out/debian-server-custom-YYYY.MM.DD-amd64.iso`

## Key Differences from Arch Installer

| Aspect | Arch | Debian |
|---|---|---|
| Bootstrap | pacstrap | debootstrap |
| Package manager | pacman | apt-get |
| Initramfs | mkinitcpio | initramfs-tools |
| Bootloader | systemd-boot | GRUB |
| Chroot | arch-chroot (auto-mounts) | Standard chroot (manual mount) |
| EFI mount | /boot | /boot/efi |
| ISO builder | archiso (mkarchiso) | live-build |
