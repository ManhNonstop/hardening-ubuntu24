#!/bin/bash
set -e

############################
# VARIABLES
############################
SSH_PORT=7722
ADMIN_USER="manhhc"
SSH_KEY=""

HOSTNAME="vm-git"
BACKUP_DIR="/root/backup_hardening_$(date +%F_%H%M%S)"

############################
# 0. BACKUP & UPDATE
############################
cp -a /etc/ssh "${BACKUP_DIR}/" || true
cp -a /etc/sysctl* "${BACKUP_DIR}/" || true
cp -a /etc/fstab "${BACKUP_DIR}/" || true

apt -y update && apt -y upgrade

############################
# 1. TIMEZONE + CHRONY
############################
timedatectl set-timezone Asia/Ho_Chi_Minh
apt update
apt install -y chrony

cat >/etc/chrony/chrony.conf <<EOF
server 0.vn.pool.ntp.org iburst
server 1.vn.pool.ntp.org iburst
server 2.vn.pool.ntp.org iburst
server 3.vn.pool.ntp.org iburst
makestep 1.0 3
rtcsync
EOF

systemctl enable --now chrony


############################
# 2. ADMIN USER + SSH KEY
############################
id "${ADMIN_USER}" &>/dev/null || useradd -m -s /bin/bash -G sudo "${ADMIN_USER}"

install -d -m 700 /home/${ADMIN_USER}/.ssh
echo "${SSH_KEY}" > /home/${ADMIN_USER}/.ssh/authorized_keys
chmod 600 /home/${ADMIN_USER}/.ssh/authorized_keys
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh

cat >/etc/sudoers.d/99-admin <<EOF
${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 /etc/sudoers.d/99-admin

############################
# 3. SSH HARDENING
############################
cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowGroups sudo
UsePAM yes
PermitTunnel no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
EOF

systemctl restart ssh

############################
# 4. PAM FAILLOCK
############################
apt install -y libpam-pwquality

cat >/etc/pam.d/common-auth <<EOF
auth required pam_faillock.so preauth silent deny=5 unlock_time=900
auth [success=1 default=ignore] pam_unix.so
auth required pam_faillock.so authfail deny=5 unlock_time=900
auth requisite pam_deny.so
auth required pam_permit.so
EOF

############################
# 5. AUDITD
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

chmod 0640 /etc/audit/rules.d/50-hardening.rules
augenrules --load
systemctl enable --now auditd

############################
# 6. FAIL2BAN + UFW
############################
apt install -y fail2ban ufw

cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
backend = systemd
action = ufw[name=default]

[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 3
bantime = 24h
EOF

systemctl enable --now fail2ban

ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 1194/udp
ufw allow 9700/udp
ufw allow 53
ufw allow 123/udp
ufw --force enable

############################
# 7. JOURNALD
############################
cat >/etc/systemd/journald.conf <<EOF
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M
EOF

systemctl restart systemd-journald

############################
# 8. SYSCTL (VPN ROUTING)
############################
cat >/etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF

sysctl --system

############################
# 9. FILESYSTEM TMP
############################
sed -i '/\/tmp/d;/\/var\/tmp/d' /etc/fstab
cat >>/etc/fstab <<EOF
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
tmpfs /var/tmp tmpfs defaults,nosuid,nodev,noexec 0 0
EOF

mount -o remount /tmp || true
mount -o remount /var/tmp || true

############################
# 10. AIDE + APPARMOR
############################
apt install -y aide apparmor-utils
aideinit
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
aa-enforce /etc/apparmor.d/* || true

############################
# 11. FINAL
############################
hostnamectl set-hostname "${HOSTNAME}"
passwd -l root || true


IP_HOST=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

if ! grep -qE "^${IP_HOST}[[:space:]]+${HOSTNAME}$" /etc/hosts; then
    echo "${IP_HOST} ${HOSTNAME}" | sudo tee -a /etc/hosts >/dev/null
    echo "✔ Đã thêm ${IP_HOST} ${HOSTNAME} vào /etc/hosts"
else
    echo "ℹ Dòng ${IP_HOST} ${HOSTNAME} đã tồn tại trong /etc/hosts"
fi

mkdir -p "${BACKUP_DIR}"

echo "======================================"
echo " HARDENING COMPLETED SUCCESSFULLY "
echo " SSH: ssh -p ${SSH_PORT} ${ADMIN_USER}@<IP>"
echo " REBOOT RECOMMENDED "
echo " REBOOTTING"

reboot
