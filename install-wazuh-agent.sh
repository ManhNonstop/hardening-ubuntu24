#!/bin/bash
set -e

### ===============================
### CONFIG (USER EDIT)
### ===============================
WAZUH_MANAGER_IP="172.16.1.5"
WAZUH_AGENT_NAME="$(hostname)"
WAZUH_VERSION="4.14"

LOG="/var/log/wazuh-agent-install.log"
: > "$LOG"

### ===============================
### FUNCTIONS
### ===============================
success() {
  echo "✅ $1: SUCCESS"
}

failed() {
  echo "❌ $1: FAILED"
  echo "------ Last logs ------"
  tail -n 20 "$LOG"
  exit 1
}

run_step() {
  STEP="$1"
  shift
  if "$@" >>"$LOG" 2>&1; then
    success "$STEP"
  else
    failed "$STEP"
  fi
}

### ===============================
### CHECK ROOT
### ===============================
run_step "CHECK_ROOT" bash -c '[[ "$EUID" -eq 0 ]]'

### ===============================
### DETECT OS
### ===============================
OS_FAMILY=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')

### ===============================
### INSTALL AGENT
### ===============================
install_deb() {
  curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
  echo "deb https://packages.wazuh.com/${WAZUH_VERSION}/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list
  apt update -y
  apt install -y wazuh-agent
}

install_rpm() {
  rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
  cat > /etc/yum.repos.d/wazuh.repo <<EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/${WAZUH_VERSION}/yum/
protect=1
EOF
  yum install -y wazuh-agent
}

case "$OS_FAMILY" in
  ubuntu|debian)
    run_step "INSTALL_AGENT" install_deb
    ;;
  rhel|centos|rocky|almalinux)
    run_step "INSTALL_AGENT" install_rpm
    ;;
  *)
    failed "UNSUPPORTED_OS"
    ;;
esac

### ===============================
### CONFIG AGENT
### ===============================
run_step "CONFIG_AGENT" bash -c "
sed -i \"s|<address>.*</address>|<address>${WAZUH_MANAGER_IP}</address>|\" /var/ossec/etc/ossec.conf &&
sed -i \"s|<name>.*</name>|<name>${WAZUH_AGENT_NAME}</name>|\" /var/ossec/etc/ossec.conf
"

### ===============================
### ENABLE & START
### ===============================
run_step "ENABLE_AGENT" systemctl enable wazuh-agent
run_step "START_AGENT" systemctl restart wazuh-agent

### ===============================
### FINISH
### ===============================
echo "===================================="
echo "✅ WAZUH AGENT INSTALLED SUCCESSFULLY"
echo "📡 Manager: ${WAZUH_MANAGER_IP}"
echo "🖥 Agent name: ${WAZUH_AGENT_NAME}"
echo "📄 Log file: $LOG"
echo "===================================="
