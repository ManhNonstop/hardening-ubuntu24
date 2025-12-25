#!/bin/bash

set -e

SITE_NAME="monitoring"
CHECKMK_DEB="check-mk-raw-2.4.0p18_0.noble_amd64.deb"
CHECKMK_URL="https://download.checkmk.com/checkmk/2.4.0p18/${CHECKMK_DEB}"
TELEGRAM_URL="https://raw.githubusercontent.com/filipnet/checkmk-telegram-notify/main/check_mk_telegram-notify.sh"

LOG_FILE="/var/log/install_checkmk.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================="
echo "🚀 BẮT ĐẦU CÀI CHECKMK RAW"
echo "=============================="

# 1. Download Checkmk
echo "📥 Download Checkmk..."
wget -q --show-progress "$CHECKMK_URL"

# 2. Cài đặt
echo "📦 Cài đặt Checkmk..."
dpkg -i "$CHECKMK_DEB" || apt -f install -y

# 3. Tạo site
if omd sites | grep -q "^${SITE_NAME}"; then
    echo "⚠️ Site ${SITE_NAME} đã tồn tại, bỏ qua bước tạo."
else
    echo "🧱 Tạo site ${SITE_NAME}..."
    omd create "$SITE_NAME"
fi

# 4. Enable autostart & start site
echo "▶️ Enable autostart cho site..."
omd config "$SITE_NAME" set AUTOSTART on

echo "▶️ Start site..."
omd start "$SITE_NAME"

# 5. Lấy thông tin login
SITE_INFO=$(omd status "$SITE_NAME")
SITE_USER="${SITE_NAME}"
SITE_PASS=$(grep "^${SITE_NAME}:" /etc/omd/sites/"${SITE_NAME}"/htpasswd | cut -d: -f2)

IP_ADDR=$(hostname -I | awk '{print $1}')

echo "=============================="
echo "✅ CHECKMK ĐÃ SẴN SÀNG"
echo "=============================="
echo "🌐 URL      : http://${IP_ADDR}/${SITE_NAME}/"
echo "👤 User     : ${SITE_USER}"
echo "🔑 Password: (password lúc tạo site – nếu quên chạy: omd su ${SITE_NAME} -> cmk-passwd ${SITE_NAME})"
echo "=============================="

# 6. Cài Telegram notify
echo "📲 Cài Telegram notification script..."

omd su "$SITE_NAME" <<EOF
cd ~/local/share/check_mk/notifications/
wget --no-check-certificate -q "$TELEGRAM_URL" -O telegram.sh
chmod ug+x telegram.sh
EOF

# 7. Restart Apache site
echo "🔄 Restart Apache site..."
omd restart apache "$SITE_NAME"

echo "=============================="
echo "🎉 HOÀN TẤT CÀI ĐẶT CHECKMK"
echo "📄 Log: ${LOG_FILE}"
echo "=============================="

