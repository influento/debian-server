# Testing the Debian Server Installer

## Hyper-V VM Setup

### 1. Get a Debian ISO

Download a Debian netboot or live ISO:

- **Netboot** (minimal, downloads packages during install — good for debootstrap):
  `https://www.debian.org/distrib/netinst`
- **Live** (includes a desktop environment for troubleshooting):
  `https://www.debian.org/CD/live/`

Save the ISO to `tests/iso/` (gitignored).

### 2. Create the VM

TODO: Create a `create-vm.ps1` script for Debian (adapt from arch-install's version).

Manual setup in Hyper-V Manager:

1. **Action -> New -> Virtual Machine**
2. **Generation 2** (UEFI), 4096 MB RAM, Default Switch, 60 GB VHDX
3. Attach the Debian ISO under Install Options
4. VM Settings: disable **Secure Boot**, set **2+ processors**, **DVD first** in boot order

### 3. Boot and Run the Installer

Start and connect to the VM:

```powershell
Start-VM -Name "DebianTest-Server"
vmconnect localhost "DebianTest-Server"
```

Boot into the live environment (or drop to a shell from the netboot installer).
Get the installer scripts in:

```bash
# Install git and debootstrap if not available
apt-get update && apt-get install -y git debootstrap

# Clone the installer
git clone https://github.com/YOUR_USER/debian-server.git /root/debian-install

# Run the installer
bash /root/debian-install/install.sh --config /root/debian-install/tests/vm-server.conf
```

**Note**: The config file pre-fills most values but passwords are still prompted
interactively. For testing, just use `test` or similar.

### 4. What to Verify After Install

- [ ] System boots to login prompt (GRUB -> kernel -> systemd)
- [ ] Can log in as the configured user
- [ ] `sudo` works
- [ ] SSH is running: `systemctl status ssh`
- [ ] Firewall is active: `sudo nft list ruleset`
- [ ] fail2ban is running: `systemctl status fail2ban`
- [ ] DNS works: `ping debian.org`
- [ ] Docker: `docker run hello-world`
- [ ] zsh is the default shell: `echo $SHELL`
- [ ] oh-my-zsh is installed: `ls ~/.oh-my-zsh`
- [ ] Correct Debian release: `cat /etc/os-release`

### 5. Hyper-V Snapshots

Use checkpoints to save state between tests:

- **Before install**: Take a checkpoint of the clean ISO boot
- **After install**: Take a checkpoint of the installed system
- Revert to the pre-install checkpoint to test again without recreating the VM
