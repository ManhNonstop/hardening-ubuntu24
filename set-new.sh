#!/bin/bash
set -e

############################
# VARIABLES
############################
SSH_PORT=2222

declare -A ADMINS

ADMINS["manhhc"]="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCv0O0zIYvp8Bx2Ns0ozFeKfDzU/DjkXBydgkNQz/neFHf++TqFjsfOdXMZ6r8+qBcIK6LUhbjiP4UEaUo8Met8JQMkIqQhD8OiH+eNEC+UxPp1wbCSgxBI8FKZX+EzHk85YqVWzsOdKfj8ZU6ga0xz4w2XUtUcLd2jVDoS2d3qUv0feJb68osntDItQndtcHUbdugFo1FSTTAZuvbBd/dYEaTUV1kcJx0tpihZ3SScEXnUFWOxZa1O0bQg+Wr5wUb+e5QuGBmKk/1VzNCEto7Yeba++FdYFb+bQ3uOw3Jpq5bGMOlESvcZe1BY2hO2jUtH2ZwlPLEcLyH00Fuy+PWF rsa-key-manhhc"

HOSTNAME="rapb-db01"
CONF_NTP="/etc/systemd/timesyncd.conf"
NTP_SERVER="10.10.110.35"

BACKUP_DIR="/root/backup_hardening_$(date +%F_%H%M%S)"

############################
# 0. BACKUP & UPDATE (FIX)
############################
mkdir -p "${BACKUP_DIR}"

echo "[*] Backup cấu hình hệ thống..."
cp -a /etc/ssh "${BACKUP_DIR}/" || true
cp -a /etc/sysctl* "${BACKUP_DIR}/" || true
cp -a /etc/fstab "${BACKUP_DIR}/" || true
cp -a /etc/pam.d "${BACKUP_DIR}/" || true

apt -y update && apt -y upgrade

############################
# 1. TIMEZONE + NTP
############################
timedatectl set-timezone Asia/Ho_Chi_Minh
sed -i "s|^#\?NTP=.*|NTP=${NTP_SERVER}|" "$CONF_NTP"
systemctl restart systemd-timesyncd

############################
# 2. ADMIN USER + SSH KEY
############################
for USER in "${!ADMINS[@]}"; do
    SSH_KEY="${ADMINS[$USER]}"

    id "$USER" &>/dev/null || useradd -m -s /bin/bash -G sudo "$USER"

    install -d -m 700 /home/$USER/.ssh
    echo "${SSH_KEY}" > /home/$USER/.ssh/authorized_keys
    chmod 600 /home/$USER/.ssh/authorized_keys
    chown -R $USER:$USER /home/$USER/.ssh
done

cat >/etc/sudoers.d/99-admin <<EOF
%sudo ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 /etc/sudoers.d/99-admin

############################
# 3. FIREWALL FIRST (FIX THỨ TỰ SSH)
############################
apt install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp
ufw --force enable

############################
# 4. SSH HARDENING (SAFE)
############################
cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowGroups sudo
UsePAM yes
X11Forwarding no
PermitTunnel no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
EOF

sshd -t
systemctl reload ssh

############################
# 5. PAM FAILLOCK (FIX ĐÚNG CÁCH)
############################
echo "[*] Cấu hình PAM faillock an toàn..."

cat >/etc/security/faillock.conf <<EOF
deny = 5
unlock_time = 900
fail_interval = 900
EOF

pam-auth-update --enable faillock

############################
# 6. AUDITD
############################
apt install -y auditd audispd-plugins

cat >/etc/audit/rules.d/50-hardening.rules <<EOF
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /usr/bin/sudo -p x -k sudo_exec
-w /var/log -p wa -k log_access
EOF

augenrules --load
systemctl enable --now auditd

############################
# 7. FAIL2BAN
############################
apt install -y fail2ban

cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 3
bantime = 24h
EOF

systemctl enable --now fail2ban

############################
# 8. SYSCTL
############################
cat >/etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF

sysctl --system

############################
# 9. TMP FILESYSTEM (FIX)
############################
sed -i '/\/tmp/d;/\/var\/tmp/d' /etc/fstab

cat >>/etc/fstab <<EOF
tmpfs /tmp tmpfs defaults,nosuid,nodev,noexec 0 0
tmpfs /var/tmp tmpfs defaults,nosuid,nodev 0 0
EOF

mount -o remount /tmp || true
mount -o remount /var/tmp || true

############################
# 10. FINAL
############################
hostnamectl set-hostname "${HOSTNAME}"
passwd -l root || true

IP_HOST=$(hostname -I | awk '{print $1}')
if ! grep -qE "^${IP_HOST}[[:space:]]+${HOSTNAME}$" /etc/hosts; then
    echo "${IP_HOST} ${HOSTNAME}" >> /etc/hosts
fi

echo "======================================"
echo " HARDENING COMPLETED SUCCESSFULLY "
echo " SSH: ssh -p ${SSH_PORT} manhhc@<IP>"
echo " BACKUP: ${BACKUP_DIR}"
echo " REBOOT RECOMMENDED "
echo "======================================"

reboot
