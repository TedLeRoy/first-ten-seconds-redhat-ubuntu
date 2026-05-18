#!/usr/bin/env bash
#
# first-ten.sh - Initial security hardening for fresh Linux servers
#
# Supports: Ubuntu 22.04+ and RHEL 9+ family (Rocky, AlmaLinux, CentOS Stream)
#
# What this script does (idempotent - safe to re-run):
#   1. Refuses to run as root; verifies sudo works up front.
#   2. Refreshes package metadata.
#   3. Enables and configures the host firewall (ufw or firewalld), allowing SSH.
#   4. Applies kernel network hardening via /etc/sysctl.d/ (rp_filter, syncookies,
#      no IP forwarding, no source routing, no redirects, log martians, etc.)
#      plus fs.suid_dumpable=0 and kernel.dmesg_restrict=1.
#   5. Hardens SSH via a drop-in /etc/ssh/sshd_config.d/ file:
#        - PermitRootLogin no
#        - IgnoreRhosts yes
#        - DisableForwarding yes
#        - DebianBanner no (Ubuntu only)
#        - PasswordAuthentication no (ONLY if authorized_keys exists AND user confirms)
#        - Modern Ciphers/MACs/KexAlgorithms/HostKeyAlgorithms only
#        - MaxAuthTries 3, LoginGraceTime 30, ClientAlive* idle disconnect ~10min
#      The drop-in is validated with `sshd -t` before sshd is reloaded.
#   6. Installs fail2ban and configures an [sshd] jail using the systemd
#      backend and a distro-appropriate banaction (ufw or firewallcmd-rich-rules).
#   7. Hardens mount options for /dev/shm (active immediately), /tmp
#      (effective on next reboot via tmp.mount), and /var/tmp (bind mount,
#      active immediately) with nosuid,nodev,noexec.
#   8. Installs and enables auditd with default rules.
#   9. Enables automatic security updates (unattended-upgrades on Ubuntu,
#      dnf-automatic on RHEL with upgrade_type=security and apply_updates=yes).
#
# Inspired by Ted LeRoy's first-ten-seconds script and Jerry Gamblin's
# "My first 10 seconds on a server" post.
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    GREEN=$(tput setaf 2)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED="" ; YELLOW="" ; GREEN="" ; BOLD="" ; RESET=""
fi

info()    { printf "%s[INFO]%s %s\n"  "$YELLOW" "$RESET" "$*"; }
ok()      { printf "%s[ OK ]%s %s\n"  "$GREEN"  "$RESET" "$*"; }
err()     { printf "%s[FAIL]%s %s\n"  "$RED"    "$RESET" "$*" >&2; }
header()  { printf "\n%s===== %s =====%s\n" "$BOLD" "$*" "$RESET"; }

# y/N confirmation; default No.
confirm() {
    local prompt="${1:-Continue?}" answer
    printf "%s%s [y/N]: %s" "$RED" "$prompt" "$RESET"
    read -r answer || return 1
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# -----------------------------------------------------------------------------
# Preflight: not root, sudo works, supported OS
# -----------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    err "Do not run this script as root."
    err "Run it as a non-root user with sudo privileges (do NOT prefix with sudo)."
    exit 1
fi

# Validate sudo up front so the script doesn't half-finish.
if ! sudo -v; then
    err "This user cannot sudo. Configure sudo and re-run."
    exit 1
fi

# Keep the sudo timestamp fresh in the background.
( while true; do sudo -n true; sleep 50; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

if [[ ! -r /etc/os-release ]]; then
    err "/etc/os-release not found; cannot identify distribution."
    exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release

DISTRO_ID="${ID:-}"
DISTRO_ID_LIKE="${ID_LIKE:-}"
DISTRO_MAJOR="${VERSION_ID:-0}"
DISTRO_MAJOR="${DISTRO_MAJOR%%.*}"

case "$DISTRO_ID" in
    ubuntu)
        FAMILY="debian"
        if (( DISTRO_MAJOR < 22 )); then
            err "Ubuntu ${VERSION_ID} is not supported (requires 22.04+)."
            exit 1
        fi
        ;;
    rhel|rocky|almalinux|centos)
        FAMILY="rhel"
        if (( DISTRO_MAJOR < 9 )); then
            err "${NAME} ${VERSION_ID} is not supported (requires version 9+)."
            exit 1
        fi
        ;;
    fedora)
        err "Fedora is not a supported target."
        err "This script targets Ubuntu 22.04+ and RHEL 9+ family"
        err "(Rocky, AlmaLinux, CentOS Stream, RHEL)."
        exit 1
        ;;
    *)
        case "$DISTRO_ID_LIKE" in
            *rhel*|*fedora*) FAMILY="rhel" ;;
            *debian*)        FAMILY="debian" ;;
            *)
                err "Unsupported distribution: ${NAME:-unknown}."
                err "This script supports Ubuntu 22.04+ and RHEL 9+ family."
                exit 1
                ;;
        esac
        ;;
esac

ok "Detected ${NAME} ${VERSION_ID} (family: ${FAMILY})"

# -----------------------------------------------------------------------------
# Cross-distro helpers
# -----------------------------------------------------------------------------

pkg_installed() {
    if [[ "$FAMILY" == "debian" ]]; then
        dpkg -s "$1" >/dev/null 2>&1
    else
        rpm -q "$1" >/dev/null 2>&1
    fi
}

pkg_install() {
    if [[ "$FAMILY" == "debian" ]]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
    else
        sudo dnf install -y "$@"
    fi
}

# EPEL handling: RHEL needs codeready-builder enabled first; Rocky/Alma/Stream
# can just install epel-release directly.
ensure_epel() {
    pkg_installed epel-release && return 0
    if [[ "$DISTRO_ID" == "rhel" ]]; then
        info "Enabling CodeReady Builder repository for RHEL ${DISTRO_MAJOR}."
        if ! sudo subscription-manager repos \
                --enable "codeready-builder-for-rhel-${DISTRO_MAJOR}-$(uname -m)-rpms"; then
            err "Could not enable CodeReady Builder. Is this RHEL system registered?"
            return 1
        fi
        sudo dnf install -y \
            "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${DISTRO_MAJOR}.noarch.rpm"
    else
        sudo dnf install -y epel-release
    fi
}

# -----------------------------------------------------------------------------
# Package metadata refresh
# -----------------------------------------------------------------------------

header "Refreshing package metadata"
if [[ "$FAMILY" == "debian" ]]; then
    sudo apt-get update -y
else
    sudo dnf -y makecache
fi
ok "Package metadata refreshed."

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------

header "Configuring host firewall"

if [[ "$FAMILY" == "debian" ]]; then
    pkg_installed ufw || pkg_install ufw
    # OpenSSH app profile if present; fall back to the ssh service name.
    sudo ufw allow OpenSSH >/dev/null 2>&1 || sudo ufw allow ssh
    sudo ufw --force enable
    ok "ufw enabled; SSH allowed."
else
    pkg_installed firewalld || pkg_install firewalld
    sudo systemctl enable --now firewalld
    if sudo firewall-cmd --permanent --list-services | tr ' ' '\n' | grep -qx ssh; then
        ok "firewalld already allows SSH."
    else
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --reload
        ok "firewalld now allows SSH."
    fi
fi

# -----------------------------------------------------------------------------
# Kernel network hardening (sysctl)
# -----------------------------------------------------------------------------

header "Applying kernel network hardening"

SYSCTL_FILE="/etc/sysctl.d/99-first-ten.conf"
TMP_SYSCTL=$(mktemp)
cat > "$TMP_SYSCTL" <<'EOF'
# Managed by first-ten.sh

# This is a server, not a router - disable IP forwarding.
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Reverse path filtering (anti-spoofing).
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects (we're not a router).
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Don't send ICMP redirects.
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Drop source-routed packets.
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log packets with impossible source addresses.
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# SYN flood protection.
net.ipv4.tcp_syncookies = 1

# Don't reply to ICMP broadcasts (smurf mitigation).
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses.
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Don't accept IPv6 router advertisements (a server shouldn't auto-config).
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Suppress SUID core dumps (prevents leaking secrets via core files).
fs.suid_dumpable = 0

# Restrict access to kernel logs (dmesg).
kernel.dmesg_restrict = 1
EOF

sudo install -m 0644 -o root -g root "$TMP_SYSCTL" "$SYSCTL_FILE"
rm -f "$TMP_SYSCTL"
# -e tolerates keys that don't exist on this kernel (e.g. IPv6 disabled).
sudo sysctl -e --system >/dev/null
ok "Kernel network hardening applied (${SYSCTL_FILE})."

# -----------------------------------------------------------------------------
# SSH hardening (drop-in + sshd -t validation)
# -----------------------------------------------------------------------------

header "Hardening SSH"

SSHD_CFG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN_FILE="${SSHD_DROPIN_DIR}/99-first-ten.conf"

# Defensive: both target distros ship with this Include line, but verify.
if ! sudo grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CFG"; then
    info "Adding 'Include ${SSHD_DROPIN_DIR}/*.conf' to sshd_config."
    echo "Include ${SSHD_DROPIN_DIR}/*.conf" | sudo tee -a "$SSHD_CFG" >/dev/null
fi
sudo mkdir -p "$SSHD_DROPIN_DIR"

# Resolve invoking user's real home from passwd, not /home/$USER.
USER_HOME=$(getent passwd "$USER" | cut -d: -f6)
AUTH_KEYS="${USER_HOME}/.ssh/authorized_keys"

DISABLE_PW_AUTH=false
if [[ -s "$AUTH_KEYS" ]]; then
    info "Found non-empty $AUTH_KEYS."
    echo
    printf "%sWARNING:%s About to consider disabling password authentication.\n" "$RED" "$RESET"
    printf "%sBefore you say yes, open a SECOND SSH session using your key%s\n" "$YELLOW" "$RESET"
    printf "%sand confirm it works. A failed key = lockout.%s\n" "$YELLOW" "$RESET"
    echo
    if confirm "Disable password authentication for SSH now?"; then
        DISABLE_PW_AUTH=true
    else
        info "Leaving password authentication enabled."
    fi
else
    info "No authorized_keys for $USER; will NOT disable password authentication."
    info "Add a key to $AUTH_KEYS and re-run to harden further."
fi

# Build the drop-in atomically.
TMP_SSHD=$(mktemp)
{
    echo "# Managed by first-ten.sh - do not edit manually."
    echo "PermitRootLogin no"
    echo "IgnoreRhosts yes"
    echo "DisableForwarding yes"
    [[ "$FAMILY" == "debian" ]] && echo "DebianBanner no"
    if [[ "$DISABLE_PW_AUTH" == "true" ]]; then
        echo "PasswordAuthentication no"
        echo "KbdInteractiveAuthentication no"
    fi

    # Session / auth limits.
    echo "MaxAuthTries 3"
    echo "LoginGraceTime 30"
    echo "ClientAliveInterval 300"
    echo "ClientAliveCountMax 2"

    # Modern crypto only. All algorithms below are supported on OpenSSH 8.7+
    # (RHEL 9) and 8.9+ (Ubuntu 22.04). Note: on RHEL these override the
    # system-wide crypto-policy for sshd specifically.
    echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256"
    echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
    echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com"
    echo "HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com"
} > "$TMP_SSHD"

sudo install -m 0644 -o root -g root "$TMP_SSHD" "$SSHD_DROPIN_FILE"
rm -f "$TMP_SSHD"

# Validate before reloading - never leave sshd in a broken state.
if sudo sshd -t; then
    ok "sshd configuration valid."
    if [[ "$FAMILY" == "debian" ]]; then
        sudo systemctl reload ssh
    else
        sudo systemctl reload sshd
    fi
    ok "sshd reloaded."
else
    err "sshd config validation FAILED. Drop-in left at ${SSHD_DROPIN_FILE} for review."
    err "Not reloading sshd. Fix the issue, then 'sudo systemctl reload sshd'."
    exit 1
fi

# -----------------------------------------------------------------------------
# fail2ban
# -----------------------------------------------------------------------------

header "Installing and configuring fail2ban"

if [[ "$FAMILY" == "rhel" ]] && ! pkg_installed fail2ban; then
    ensure_epel
fi

pkg_installed fail2ban || pkg_install fail2ban

# Banaction that matches the native firewall stack on each distro.
if [[ "$FAMILY" == "debian" ]]; then
    BAN_ACTION="ufw"
else
    BAN_ACTION="firewallcmd-rich-rules"
fi

JAIL_LOCAL="/etc/fail2ban/jail.local"

# Preserve any pre-existing jail.local that isn't ours.
if [[ -f "$JAIL_LOCAL" ]] && ! sudo grep -q "Managed by first-ten.sh" "$JAIL_LOCAL"; then
    BACKUP="${JAIL_LOCAL}.bak.$(date +%s)"
    info "Backing up existing $JAIL_LOCAL to $BACKUP"
    sudo cp -a "$JAIL_LOCAL" "$BACKUP"
fi

TMP_JAIL=$(mktemp)
cat > "$TMP_JAIL" <<EOF
# Managed by first-ten.sh
# To customize without losing changes on re-run, drop overrides into
# /etc/fail2ban/jail.d/ instead of editing this file.

[DEFAULT]
backend   = systemd
banaction = ${BAN_ACTION}
findtime  = 12h
bantime   = 24h
maxretry  = 5

[sshd]
enabled = true
EOF

sudo install -m 0644 -o root -g root "$TMP_JAIL" "$JAIL_LOCAL"
rm -f "$TMP_JAIL"

sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
ok "fail2ban active (sshd jail: maxretry=5, findtime=12h, bantime=24h)."

# -----------------------------------------------------------------------------
# Filesystem mount hardening (/tmp, /var/tmp, /dev/shm)
# -----------------------------------------------------------------------------

header "Hardening /tmp, /var/tmp, /dev/shm mount options"

# --- /dev/shm: noexec,nosuid,nodev -------------------------------------------
if grep -qE '^\s*tmpfs\s+/dev/shm\s+' /etc/fstab; then
    info "Updating /dev/shm options in /etc/fstab."
    sudo sed -i.bak \
        -E 's|^(\s*tmpfs\s+/dev/shm\s+tmpfs\s+)[^[:space:]]+(.*)$|\1defaults,noexec,nosuid,nodev\2|' \
        /etc/fstab
else
    info "Adding /dev/shm entry to /etc/fstab."
    echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" | \
        sudo tee -a /etc/fstab >/dev/null
fi
# Let systemd see the fstab change before we remount, otherwise mount(8) prints
# a "fstab modified, systemd still uses the old version" hint.
sudo systemctl daemon-reload
sudo mount -o remount /dev/shm
ok "/dev/shm: noexec,nosuid,nodev (active now)."

# --- /tmp: hardened tmp.mount drop-in ----------------------------------------
# NOTE: enabling tmp.mount makes /tmp a tmpfs (RAM-backed, sized to 50% of RAM).
# Effective on next reboot to avoid disrupting anything currently using /tmp.
sudo mkdir -p /etc/systemd/system/tmp.mount.d
TMP_DROPIN=$(mktemp)
cat > "$TMP_DROPIN" <<'EOF'
# Managed by first-ten.sh
[Mount]
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=50%
EOF
sudo install -m 0644 -o root -g root "$TMP_DROPIN" /etc/systemd/system/tmp.mount.d/override.conf
rm -f "$TMP_DROPIN"
sudo systemctl daemon-reload
sudo systemctl enable tmp.mount >/dev/null 2>&1 || true
ok "/tmp: tmp.mount enabled with nosuid,nodev,noexec (effective on next reboot)."

# --- /var/tmp: bind-mount on itself with hardening ---------------------------
VARTMP_UNIT=$(mktemp)
cat > "$VARTMP_UNIT" <<'EOF'
# Managed by first-ten.sh
[Unit]
Description=Hardened bind mount for /var/tmp
DefaultDependencies=no
Conflicts=umount.target
Before=local-fs.target umount.target
ConditionPathIsSymbolicLink=!/var/tmp

[Mount]
What=/var/tmp
Where=/var/tmp
Type=none
Options=bind,nosuid,nodev,noexec

[Install]
WantedBy=local-fs.target
EOF
sudo install -m 0644 -o root -g root "$VARTMP_UNIT" /etc/systemd/system/var-tmp.mount
rm -f "$VARTMP_UNIT"
sudo systemctl daemon-reload
sudo systemctl enable --now var-tmp.mount
ok "/var/tmp: bind-mounted with nosuid,nodev,noexec (active now)."

# -----------------------------------------------------------------------------
# Audit logging (auditd)
# -----------------------------------------------------------------------------

header "Enabling audit logging"

# Package name differs: 'auditd' on Debian-family, 'audit' on RHEL-family.
if [[ "$FAMILY" == "debian" ]]; then
    pkg_installed auditd || pkg_install auditd
else
    pkg_installed audit || pkg_install audit
fi
sudo systemctl enable --now auditd
ok "auditd active (default rules; add custom rules to /etc/audit/rules.d/)."

# -----------------------------------------------------------------------------
# Automatic security updates
# -----------------------------------------------------------------------------

header "Enabling automatic security updates"

if [[ "$FAMILY" == "debian" ]]; then
    pkg_installed unattended-upgrades || pkg_install unattended-upgrades
    # Write the periodic config non-interactively.
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    sudo systemctl enable --now unattended-upgrades
    ok "unattended-upgrades enabled."
else
    pkg_installed dnf-automatic || pkg_install dnf-automatic
    sudo sed -i \
        -e 's/^upgrade_type.*/upgrade_type = security/' \
        -e 's/^apply_updates.*/apply_updates = yes/'   \
        /etc/dnf/automatic.conf
    sudo systemctl enable --now dnf-automatic.timer
    ok "dnf-automatic.timer enabled (security updates, auto-apply)."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

header "Summary"

PW_LINE="PasswordAuthentication: unchanged"
[[ "$DISABLE_PW_AUTH" == "true" ]] && PW_LINE="PasswordAuthentication: disabled (KEY-ONLY)"

FW_LINE="firewalld enabled, SSH allowed"
[[ "$FAMILY" == "debian" ]] && FW_LINE="ufw enabled, SSH allowed"

UPD_LINE="dnf-automatic (security updates)"
[[ "$FAMILY" == "debian" ]] && UPD_LINE="unattended-upgrades"

cat <<EOF
${GREEN}Hardening complete on ${NAME} ${VERSION_ID}.${RESET}

  Firewall:       ${FW_LINE}
  Sysctl:         ${SYSCTL_FILE}
                  - rp_filter, syncookies, log_martians
                  - no IP forwarding / source routing / redirects
                  - fs.suid_dumpable=0, kernel.dmesg_restrict=1
  SSH drop-in:    ${SSHD_DROPIN_FILE}
                  - PermitRootLogin no, IgnoreRhosts yes, DisableForwarding yes
$( [[ "$FAMILY" == "debian" ]] && echo "                  - DebianBanner no" )
                  - ${PW_LINE}
                  - MaxAuthTries 3, LoginGraceTime 30
                  - ClientAliveInterval 300 / CountMax 2 (~10min idle)
                  - Modern Ciphers/MACs/Kex/HostKey only
  fail2ban:       active, [sshd] jail using ${BAN_ACTION}
  Mount options:  /dev/shm and /var/tmp hardened NOW
                  /tmp hardened on NEXT REBOOT (via tmp.mount)
  auditd:         active with default ruleset
  Auto updates:   ${UPD_LINE}

${YELLOW}IMPORTANT:${RESET} verify you can still SSH in from a NEW session
before closing this one. If something is wrong, you can revert by removing
${SSHD_DROPIN_FILE} and reloading sshd.

${YELLOW}NOTE:${RESET} /tmp will become a tmpfs (RAM-backed, 50% of RAM) on
next reboot. Any files currently in /tmp will be masked (not deleted) once
the tmpfs is mounted. Move anything you need to keep out of /tmp first.
EOF
