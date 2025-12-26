#!/bin/bash
set -e

### ===============================
### USER CONFIG
### ===============================
WAZUH_MANAGER="172.16.1.5"
DEFAULT_GROUP="vm-core"
AGENT_NAME="$(hostname)"
WAZUH_VERSION="4.14.1"

LOG="/var/log/wazuh-agent-install.log"
: > "$LOG"

### ===============================
### FUNCTIONS
### ===============================
success() { echo "✅ $1: SUCCESS"; }
fail() {
  echo "❌ $1: FAILED"
  tail -n 20 "$LOG"
  exit 1
}

run() {
  STEP="$1"; shift
  if "$@" >>"$LOG" 2>&1; then
    success "$STEP"
  else
    fail "$STEP"
  fi
}

### ===============================
### CHECK ROOT
### ===============================
run "CHECK_ROOT" bash -c '[[ "$EUID" -eq 0 ]]'

### ===============================
### DETECT OS
### ===============================
source /etc/os-release
OS_ID="$ID"
ARCH="$(uname -m)"

[[ "$ARCH" != "x86_64" ]] && fail "ARCH_NOT_SUPPORTED"

### ===============================
### INSTALL FUNCTIONS
### ===============================
install_deb() {
  PKG="wazuh-agent_${WAZUH_VERSION}-1_amd64.deb"
  URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/${PKG}"

  wget -q $URL
  WAZUH_MANAGER="$WAZUH_MANAGER" \
  WAZUH_AGENT_GROUP="$GROUP" \
  WAZUH_AGENT_NAME="$AGENT_NAME" \
  dpkg -i $PKG
}

install_rpm() {
  PKG="wazuh-agent-${WAZUH_VERSION}-1.x86_64.rpm"
  URL="https://packages.wazuh.com/4.x/yum/${PKG}"

  rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
  wget -q $URL

  WAZUH_MANAGER="$WAZUH_MANAGER" \
  WAZUH_AGENT_GROUP="$GROUP" \
  WAZUH_AGENT_NAME="$AGENT_NAME" \
  rpm -ivh $PKG
}

### ===============================
### GROUP INPUT
### ===============================
GROUP="${1:-$DEFAULT_GROUP}"

### ===============================
### INSTALL AGENT
### ===============================
case "$OS_ID" in
  ubuntu|debian)
    run "INSTALL_AGENT" install_deb
    ;;
  rhel|centos|rocky|almalinux|ol|amzn)
    run "INSTALL_AGENT" install_rpm
    ;;
  *)
    fail "UNSUPPORTED_OS"
    ;;
esac

### ===============================
### ENABLE & START
### ===============================
run "ENABLE_AGENT" systemctl enable wazuh-agent
run "START_AGENT" systemctl restart wazuh-agent

### ===============================
### FINISH
### ===============================
echo "======================================"
echo "✅ WAZUH AGENT INSTALLATION COMPLETED"
echo "📡 Manager : $WAZUH_MANAGER"
echo "🖥 Agent   : $AGENT_NAME"
echo "🧩 Group   : $GROUP"
echo "📄 Log     : $LOG"
echo "======================================"
