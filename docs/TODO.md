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

## Security Hardening (suggested)

Known security trade-offs in the current design, surfaced during a security review.
None block the current use case; each lists the issue and a suggested fix.

- [ ] **Restrict Docker published ports to the firewall policy** — `docker run -p 80:80`
  bypasses the nftables `input` drop policy. Docker DNATs inbound traffic, so it arrives as
  *forwarded* (not input) traffic, and the `forward` chain blanket-accepts `docker0`/`br-*` —
  leaving any published port reachable from the whole network despite "only SSH open."
  *Fix:* set `/etc/docker/daemon.json` to `{ "ip": "127.0.0.1" }` so `-p` binds to loopback by
  default (use an explicit `-p 0.0.0.0:…` or a reverse proxy to expose a service publicly), or
  add a `DOCKER-USER` drop chain scoped to trusted subnets.
  *(modules/docker.sh, modules/firewall.sh)*

- [ ] **SSH key-only auth option** — `PasswordAuthentication yes` is the default; combined with
  NOPASSWD sudo, a guessed or brute-forced user password is effectively remote root (fail2ban is
  the only barrier). *Fix:* accept an SSH public key (config var, file path, or
  `github.com/<user>.keys`), install it to the user's `authorized_keys`, and set
  `PasswordAuthentication no` **only when a key is supplied** (opt-in → no lockout risk).
  *(modules/ssh.sh, install.sh)*

- [ ] **Reconsider NOPASSWD sudo** — `%sudo ALL=(ALL:ALL) NOPASSWD: ALL` lets any local process
  running as the user escalate to root with no re-authentication. *Fix (optional):* gate behind a
  flag or require a sudo password. Lower priority once SSH is key-only. *(lib/configure.sh)*

## Future

- [ ] Unattended upgrades (automatic security updates)
- [ ] fail2ban custom jail configuration
- [ ] LUKS encryption support
