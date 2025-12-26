#!/bin/bash
set -e

### ===== USER CONFIG =====
WAZUH_MANAGER="172.16.1.5"
AGENT_GROUP="${1:-default}"
AGENT_NAME="$(hostname)"
VERSION="4.14.1"

PKG="wazuh-agent_${VERSION}-1_amd64.deb"
URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/${PKG}"

### ======================
echo "➡ Installing Wazuh Agent"
echo "   Manager : $WAZUH_MANAGER"
echo "   Group   : $AGENT_GROUP"
echo "   Name    : $AGENT_NAME"

wget -q $URL

sudo WAZUH_MANAGER="$WAZUH_MANAGER" \
     WAZUH_AGENT_GROUP="$AGENT_GROUP" \
     WAZUH_AGENT_NAME="$AGENT_NAME" \
     dpkg -i $PKG

systemctl enable wazuh-agent --now

echo "✅ INSTALL SUCCESS"
