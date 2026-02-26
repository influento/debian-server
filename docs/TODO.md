# TODO

## Completed

- [x] Project scaffold (from arch-install)
- [x] Core implementation (all lib/*.sh, modules/*.sh, profiles/*.sh)
- [x] Dotfiles integration (DOTFILES_REPO, bundled on ISO, deploy_dotfiles)
- [x] Custom ISO builder (Docker + live-build, package cache)
- [x] Hyper-V VM testing (create-vm.ps1, VM-tested through user setup)

## In Progress

- [ ] Complete end-to-end VM test (reboot into installed system, verify services)
- [ ] Test on physical hardware (mini PC)

## Post-install Verification Checklist

- [ ] SSH: `systemctl status ssh`
- [ ] Firewall: `sudo nft list ruleset`
- [ ] fail2ban: `systemctl status fail2ban`
- [ ] Docker: `docker run hello-world`
- [ ] DNS: `ping debian.org`
- [ ] Shell: `echo $SHELL` → `/usr/bin/zsh`
- [ ] Dotfiles: `ls ~/.dotfiles`, `git -C ~/.dotfiles remote -v`

## Future

- [ ] Unattended upgrades (automatic security updates)
- [ ] fail2ban custom jail configuration
- [ ] SSH key-only auth option
- [ ] Unattended mode (fully non-interactive from config file)
- [ ] LUKS encryption support
