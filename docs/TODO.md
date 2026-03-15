# TODO

## Completed

- [x] Project scaffold (from arch-install)
- [x] Core implementation (all lib/*.sh, modules/*.sh, profiles/*.sh)
- [x] Dotfiles integration (DOTFILES_REPO, bundled on ISO, deploy_dotfiles)
- [x] Custom ISO builder (Docker + live-build, package cache)
- [x] Hyper-V VM testing (create-vm.ps1, VM-tested through user setup)
- [x] QEMU/KVM VM testing (create-vm.sh, headless + SSH, end-to-end verified)
- [x] Unattended mode (fully non-interactive from config file)
- [x] End-to-end VM test (reboot, verify all services)

## In Progress

- [ ] Test on physical hardware (mini PC)

## Post-install Verification Checklist

- [x] SSH: `systemctl status ssh`
- [x] Firewall: `sudo nft list ruleset`
- [x] fail2ban: `systemctl status fail2ban`
- [x] Docker: `docker run hello-world`
- [x] DNS: `ping debian.org`
- [x] Shell: `echo $SHELL` → `/usr/bin/zsh`
- [x] Dotfiles: `ls ~/dev/infra/dotfiles`, `git -C ~/dev/infra/dotfiles remote -v`
- [x] Sudo: `sudo whoami` (NOPASSWD)
- [x] Reboot persistence: services survive reboot

## Future

- [ ] Unattended upgrades (automatic security updates)
- [ ] fail2ban custom jail configuration
- [ ] SSH key-only auth option
- [ ] LUKS encryption support
