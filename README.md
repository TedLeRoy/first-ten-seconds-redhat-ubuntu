![First-ten-post-run](https://i.ibb.co/4N5QXww/After-Running-Script.png)

# first-ten-seconds-redhat-ubuntu

A bash script to help perform initial security hardening on a freshly installed
**Ubuntu 22.04+** or **RHEL 9+** family server (Rocky Linux, AlmaLinux,
CentOS Stream) quickly and easily.

### Background

> Note: this project was renamed from `first-ten-seconds-centos-ubuntu` to
> `first-ten-seconds-redhat-ubuntu` when CentOS Linux 8 was discontinued. It now
> targets the modern RHEL 9 family (Rocky, AlmaLinux, CentOS Stream, RHEL) and
> Ubuntu 22.04+.

This script doesn't fully "lock down" your server, but it raises the baseline
security posture so you can either move on to more in-depth hardening or be up
and running quickly if this gives you what you need.

Inspired by Jerry Gamblin's blog post:
<https://jerrygamblin.com/2016/07/13/my-first-10-seconds-on-a-server/>, Bryan
Kennedy's "My First 5 Minutes On A Server" post, various DigitalOcean guides,
and Red Hat and Ubuntu security best practices.

The script auto-detects which distribution it's running on (via
`/etc/os-release`) and applies the appropriate commands. It also verifies a
supported OS version before doing anything, refuses to run as root, and
validates the SSH config with `sshd -t` before reloading sshd so a typo can't
lock you out.

It is strongly recommended to only run this on clean installs, after a
non-root user with sudo permission has been set up and **key-based SSH
authentication has been configured and tested for that user**.

The following tutorials can help you set up key-based authentication:

- YouTube series (parts 1–7) for key-based authentication on Ubuntu:
  <https://www.youtube.com/watch?v=ugpAr5fhA1s>
- DigitalOcean — How to set up SSH keys on Rocky Linux 9:
  <https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-rocky-linux-9>
- DigitalOcean — How to set up SSH keys on Ubuntu:
  <https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu>

### Project Goals

Roll a focused set of security best practices for new servers into a single
script that detects the distribution it's running on and applies the
appropriate commands for that OS. Stay small enough to read end-to-end (not a
full CIS Benchmark implementation), and be safe to re-run (idempotent).

### What It Does

The same set of hardening steps is applied to both Ubuntu and the RHEL family;
implementation details differ where the distros differ (e.g. ufw vs firewalld,
apt vs dnf).

1. **Preflight checks**

   - Refuses to run as root.
   - Verifies the invoking user has sudo, prompts once, then keeps the sudo
     timestamp fresh in the background.
   - Detects distribution and version; bails out on anything older than
     Ubuntu 22.04 or RHEL 9.

2. **Package metadata refresh** — `apt-get update` or `dnf makecache`.

3. **Host firewall**

   - Ubuntu: installs and enables `ufw`, allows SSH.
   - RHEL family: installs and enables `firewalld`, allows the SSH service.

4. **Kernel network hardening** — a single drop-in at
   `/etc/sysctl.d/99-first-ten.conf` enabling:

   - Reverse path filtering, SYN cookies, log martians.
   - No IP forwarding, no source routing, no ICMP redirects (sent or received).
   - No IPv6 router advertisements.
   - `fs.suid_dumpable=0` (no core dumps from SUID binaries).
   - `kernel.dmesg_restrict=1` (only root reads kernel logs).

5. **SSH hardening** via a drop-in at
   `/etc/ssh/sshd_config.d/99-first-ten.conf`. The drop-in is validated with
   `sshd -t` before sshd is reloaded.

   - `PermitRootLogin no`
   - `IgnoreRhosts yes`
   - `DisableForwarding yes`
   - `DebianBanner no` (Ubuntu only)
   - `PasswordAuthentication no` — **only** if `authorized_keys` is present
     for the invoking user **and** the user confirms at the prompt. You're
     warned to open a second SSH session and verify your key works before
     confirming.
   - `MaxAuthTries 3`, `LoginGraceTime 30`, `ClientAliveInterval 300`,
     `ClientAliveCountMax 2` (~10 min idle disconnect).
   - Modern crypto only: curve25519, chacha20-poly1305 and AES-GCM ciphers,
     ETM MACs, ed25519 host keys.

6. **fail2ban** — installs fail2ban (pulling in EPEL on RHEL when needed) and
   configures an `[sshd]` jail using the `systemd` backend (so it works the
   same on both distros without log-path differences) with a distro-appropriate
   banaction (`ufw` on Ubuntu, `firewallcmd-rich-rules` on RHEL).

7. **Filesystem mount hardening** — `nosuid,nodev,noexec` applied to:

   - `/dev/shm` — via `/etc/fstab`, remounted immediately.
   - `/tmp` — systemd `tmp.mount` enabled with a hardened drop-in.
     **Effective on next reboot.** Note that this converts `/tmp` to a tmpfs
     sized at 50% of RAM; anything currently in `/tmp` is masked (not
     deleted) once the tmpfs mounts.
   - `/var/tmp` — bind-mounted onto itself with hardened options via a
     systemd `.mount` unit, active immediately.

8. **auditd** — installed and enabled with the default ruleset. Add your own
   rules under `/etc/audit/rules.d/` to customize.

9. **Automatic security updates**

   - Ubuntu: `unattended-upgrades` plus `/etc/apt/apt.conf.d/20auto-upgrades`
     to enable daily updates and unattended upgrades.
   - RHEL family: `dnf-automatic` configured with `upgrade_type = security`
     and `apply_updates = yes`, then `dnf-automatic.timer` enabled.

### Prerequisites

You must have sudo permissions to run the commands inside the script. The
script should **not** be run as root — run it as your non-root sudo-enabled
user and enter sudo credentials when prompted.

The script will give you the greatest benefit (and protect you from a
lockout) if key-based SSH authentication is set up and tested before you run
it.

### Warning

Be sure you've read and understand what this script does before running it.
You can read the man page for each command and option to see what it does.

Any time the creator of a script says it has to be run with sudo permissions
or as root, understand why and use caution.

***This script must be run by a user with sudo permissions because the
firewall, package, sshd, sysctl, mount, and service commands it uses require
root. It should be run as a non-root user; sudo credentials are entered when
prompted.***

A couple of behavior notes worth flagging:

- The `/tmp` change becomes effective on next reboot and switches `/tmp` to
  tmpfs (RAM-backed). On very small VMs this can be tight — adjust the
  `size=50%` in `/etc/systemd/system/tmp.mount.d/override.conf` if needed.
- The strict SSH crypto list excludes very old algorithms. Any reasonably
  modern SSH client works fine; ancient clients may need the list relaxed.
- The script is idempotent — safe to re-run if something fails midway.

### Usage

The latest version of this script can be run with the following one-liner on
a fresh Ubuntu 22.04+ or RHEL 9+ server, after a non-root user with sudo
privileges has been set up and key-based SSH authentication for that user
is configured:

```
bash <(curl -s https://raw.githubusercontent.com/TedLeRoy/first-ten-seconds-redhat-ubuntu/master/first-ten.sh)
```

Alternatively, download and run it locally so you can review it first
(recommended):

```
wget https://raw.githubusercontent.com/TedLeRoy/first-ten-seconds-redhat-ubuntu/master/first-ten.sh
less first-ten.sh        # review before running
chmod +x first-ten.sh
./first-ten.sh
```

Or clone the repository:

```
git clone https://github.com/TedLeRoy/first-ten-seconds-redhat-ubuntu.git
cd first-ten-seconds-redhat-ubuntu
./first-ten.sh
```

### Issues, Feature Requests, Input

Please report issues, request features, or provide input or feedback about
the script
[here](https://github.com/TedLeRoy/first-ten-seconds-redhat-ubuntu/issues).

