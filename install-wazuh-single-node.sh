#!/bin/bash
set -e

### ===============================
### CONFIG
### ===============================
MIN_CPU=4
MIN_RAM_GB=8
MIN_DISK_GB=50
WAZUH_VERSION="4.14"

WORKDIR="/root/wazuh-install"
LOG="/var/log/wazuh-install.log"

HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')

mkdir -p $(dirname $LOG)
: > $LOG

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
  STEP_NAME="$1"
  shift
  if "$@" >>"$LOG" 2>&1; then
    success "$STEP_NAME"
  else
    failed "$STEP_NAME"
  fi
}

### ===============================
### CHECK RESOURCE
### ===============================
check_resources() {
  CPU=$(nproc)
  RAM=$(free -g | awk '/^Mem:/{print $2}')
  DISK=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

  [[ $CPU -ge $MIN_CPU ]] \
  && [[ $RAM -ge $MIN_RAM_GB ]] \
  && [[ $DISK -ge $MIN_DISK_GB ]]
}

run_step "CHECK_RESOURCES" check_resources

### ===============================
### PREPARE ENV
### ===============================
run_step "PREPARE_ENV" bash -c "
apt update -y &&
apt install -y curl tar &&
mkdir -p $WORKDIR
"

cd $WORKDIR || failed "WORKDIR"

### ===============================
### DOWNLOAD INSTALLER
### ===============================
run_step "DOWNLOAD_INSTALLER" bash -c "
curl -sO https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh &&
curl -sO https://packages.wazuh.com/${WAZUH_VERSION}/config.yml &&
chmod +x wazuh-install.sh
"

### ===============================
### GENERATE CONFIG
### ===============================
run_step "GENERATE_CONFIG" bash -c "
cat > config.yml <<EOF
nodes:
  indexer:
    - name: ${HOSTNAME}
      ip: ${IP}
  server:
    - name: ${HOSTNAME}
      ip: ${IP}
  dashboard:
    - name: ${HOSTNAME}
      ip: ${IP}
EOF
"

### ===============================
### GENERATE CERT
### ===============================
run_step "GENERATE_CERTS" bash wazuh-install.sh --generate-config-files

### ===============================
### INSTALL INDEXER
### ===============================
run_step "INSTALL_INDEXER" bash wazuh-install.sh --wazuh-indexer ${HOSTNAME}

### ===============================
### START CLUSTER
### ===============================
run_step "START_CLUSTER" bash wazuh-install.sh --start-cluster

### ===============================
### INSTALL SERVER
### ===============================
run_step "INSTALL_SERVER" bash wazuh-install.sh --wazuh-server ${HOSTNAME}

### ===============================
### INSTALL DASHBOARD
### ===============================
run_step "INSTALL_DASHBOARD" bash wazuh-install.sh --wazuh-dashboard ${HOSTNAME}

### ===============================
### SHOW RESULT
### ===============================
echo "✅ INSTALLATION_FINISHED: SUCCESS"
echo "📄 Log file: $LOG"
echo "🌐 Dashboard: https://${IP}"
