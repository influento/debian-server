# Testing the Debian Server Installer

## Directory Layout

```
tests/
├── linux/              # QEMU/KVM scripts (Linux host)
│   ├── create-vm.sh
│   └── download-iso.sh
├── windows/            # Hyper-V scripts (Windows host)
│   └── create-vm.ps1
├── vm-server.conf      # Shared VM test config
└── README.md
```

## Building the Custom ISO

Builds a custom live ISO with the installer pre-loaded. Requires Docker.

```bash
docker build -t debian-iso-builder iso/
docker run --rm --privileged -v "$(pwd)":/build -v debian-iso-cache:/cache debian-iso-builder
```

Output: `iso/out/debian-server-custom-*.iso`

On boot, the ISO auto-launches the installer menu via `start.sh`.

---

## Linux (QEMU/KVM)

### Prerequisites

- `qemu-full` (provides `qemu-system-x86_64`)
- `edk2-ovmf` (UEFI firmware)
- KVM enabled (check: `lsmod | grep kvm`)

### 1. Download the ISO

```bash
./tests/linux/download-iso.sh
```

Downloads the latest Debian netinst ISO, verifies SHA256 and GPG signature. Saves to `tests/iso/`.

Options:
- `--force` — re-download even if ISO exists
- `--skip-gpg` — skip GPG signature verification

### 2. Create and Launch the VM

```bash
./tests/linux/create-vm.sh
```

Creates a UEFI VM with QEMU/KVM and launches it immediately:
- 4 GB RAM, 2 CPUs, 60 GB VirtIO disk
- OVMF UEFI firmware (no Secure Boot)
- User-mode networking (internet access, no root required)
- ISO auto-detected (prefers custom from `iso/out/`, falls back to `tests/iso/`)
- QEMU monitor on stdio for VM control

Options:
- `--name NAME` — VM name (default: `debiantest`)
- `--memory MB` — RAM in MB (default: `4096`)
- `--cpus N` — number of CPUs (default: `2`)
- `--disk-size GB` — disk size in GB (default: `60`)
- `--iso PATH` — use a specific ISO
- `--no-launch` — create disk and print command without launching

### 3. Run the Install

Boot into the live environment or netinst shell, then run:

```bash
bash /root/debian-install/start.sh
```

If using a stock ISO (not the custom one), clone the repo first:

```bash
apt-get update && apt-get install -y git debootstrap
git clone https://github.com/YOUR_USER/debian-server.git /root/debian-install
bash /root/debian-install/install.sh --config /root/debian-install/tests/vm-server.conf
```

### 4. Cleanup

To retest from scratch:

```bash
rm tests/vm/debiantest.qcow2 tests/vm/debiantest_VARS.fd
./tests/linux/create-vm.sh
```

---

## Windows (Hyper-V)

### 1. Create the VM

From an elevated PowerShell prompt:

```powershell
.\tests\windows\create-vm.ps1
```

Creates a Gen 2 UEFI VM with:
- Secure Boot disabled, DVD boot first
- 4 GB RAM, 60 GB dynamic VHDX, 2 vCPUs
- Connected to Default Switch (or first External switch)

**Note:** Update `$ISOPath` in the script to point to your ISO.

### 2. Boot and Run

```powershell
Start-VM -Name "debian-server-test"
vmconnect localhost "debian-server-test"
```

### 3. Cleanup

```powershell
Stop-VM -Name "debian-server-test" -Force
Remove-VM -Name "debian-server-test" -Force
```

---

## VM Test Config

The shared config `tests/vm-server.conf` works with both hypervisors.

**Note:** `TARGET_DISK` is set to `/dev/vda` (QEMU VirtIO). If testing with
Hyper-V, change it to `/dev/sda`.

---

## What to Verify After Install

- [ ] System boots to login prompt (GRUB -> kernel -> systemd)
- [ ] Can log in as the configured user
- [ ] `sudo` works (NOPASSWD)
- [ ] SSH is running: `systemctl status ssh`
- [ ] Firewall is active: `sudo nft list ruleset`
- [ ] fail2ban is running: `systemctl status fail2ban`
- [ ] DNS works: `ping debian.org`
- [ ] Docker: `docker run hello-world`
- [ ] zsh is the default shell: `echo $SHELL`
- [ ] Dotfiles deployed: `ls ~/.dotfiles`, `git -C ~/.dotfiles remote -v`
- [ ] Correct Debian release: `cat /etc/os-release` (Trixie)

## Physical Hardware Testing

1. Flash the custom ISO to USB (Ventoy or `dd`)
2. Boot from USB on the target machine
3. Run `bash /root/debian-install/start.sh`
4. Select install, answer prompts, walk away
5. Verify using the checklist above after reboot
