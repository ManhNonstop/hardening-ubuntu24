#!/bin/bash

SITE_NAME="monitoring"
CHECKMK_DEB="check-mk-raw-2.4.0p18_0.noble_amd64.deb"
CHECKMK_URL="https://download.checkmk.com/checkmk/2.4.0p18/${CHECKMK_DEB}"
TELEGRAM_URL="https://raw.githubusercontent.com/filipnet/checkmk-telegram-notify/main/check_mk_telegram-notify.sh"
LOG_FILE="/var/log/install_checkmk.log"

mkdir -p /var/log
: > "$LOG_FILE"

IP=$(hostname -I | awk '{print $1}')
PASSWORD=""

ok()   { echo "✅ $1"; }
fail() { echo "❌ $1"; echo "   👉 Xem log: $LOG_FILE"; exit 1; }

run() {
    DESC="$1"
    shift
    "$@" >>"$LOG_FILE" 2>&1 && ok "$DESC" || fail "$DESC"
}

echo "=============================="
echo "🚀 CÀI ĐẶT CHECKMK RAW"
echo "=============================="

# 1. Download
run "Download Checkmk" wget -q "$CHECKMK_URL"

# 2. Install
if dpkg -i "$CHECKMK_DEB" >>"$LOG_FILE" 2>&1; then
    ok "Cài đặt Checkmk"
else
    run "Fix dependency" apt -f install -y
fi

# 3. Create site (ONE TIME ONLY)
if omd sites | grep -qx "$SITE_NAME"; then
    ok "Site ${SITE_NAME} đã tồn tại (skip tạo site)"
    PASSWORD="(site đã tồn tại – reset bằng cmk-passwd cmkadmin)"
else
    echo "⏳ Đang tạo site ${SITE_NAME}..."
    CREATE_OUTPUT=$(omd create "$SITE_NAME" 2>&1 | tee -a "$LOG_FILE") || fail "Tạo site ${SITE_NAME}"
    PASSWORD=$(echo "$CREATE_OUTPUT" | grep "password:" | awk '{print $NF}')
    [ -n "$PASSWORD" ] || fail "Không lấy được password site"
    ok "Tạo site ${SITE_NAME}"
fi

# 4. Enable autostart
run "Enable autostart site" omd config "$SITE_NAME" set AUTOSTART on

# 5. Start site (DETACHED – START ONCE)
omd start "$SITE_NAME"

# 6. Telegram notify (NON-BLOCKING)
if timeout 15 omd su "$SITE_NAME" -c \
"mkdir -p ~/local/share/check_mk/notifications && \
 cd ~/local/share/check_mk/notifications && \
 wget --no-check-certificate -q $TELEGRAM_URL -O telegram.sh && \
 chmod ug+x telegram.sh" >>"$LOG_FILE" 2>&1; then
    ok "Cài Telegram notification"
else
    echo "⚠️ Telegram notify không cài được (bỏ qua)"
fi

# 7. Final info
echo ""
echo "======================================"
echo "🎉 CHECKMK CÀI ĐẶT HOÀN TẤT"
echo "======================================"
echo "Link login : http://${IP}/${SITE_NAME}"
echo "Username   : cmkadmin"
echo "Password   : ${PASSWORD}"
echo "Log file   : ${LOG_FILE}"
echo "======================================"
