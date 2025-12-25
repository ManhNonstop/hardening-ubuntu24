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

print_ok()   { echo "✅ $1"; }
print_fail() { echo "❌ $1"; echo "   👉 Xem log: $LOG_FILE"; }

run_step() {
    DESC="$1"
    shift
    if "$@" >>"$LOG_FILE" 2>&1; then
        print_ok "$DESC"
    else
        print_fail "$DESC"
        exit 1
    fi
}

echo "=============================="
echo "🚀 CÀI ĐẶT CHECKMK RAW"
echo "=============================="

# 1. Download
run_step "Download Checkmk" wget -q "$CHECKMK_URL"

# 2. Install
if dpkg -i "$CHECKMK_DEB" >>"$LOG_FILE" 2>&1; then
    print_ok "Cài đặt Checkmk"
else
    run_step "Fix dependency" apt -f install -y
fi

# 3. Create site
if omd sites | grep -q "^${SITE_NAME}"; then
    print_ok "Site ${SITE_NAME} đã tồn tại (skip tạo site)"
    PASSWORD="(site đã tồn tại – reset bằng cmk-passwd cmkadmin)"
else
    CREATE_OUTPUT=$(omd create "$SITE_NAME" >>"$LOG_FILE" 2>&1 || true)
    PASSWORD=$(echo "$CREATE_OUTPUT" | grep "password:" | awk '{print $NF}')
    if [[ -n "$PASSWORD" ]]; then
        print_ok "Tạo site ${SITE_NAME}"
    else
        print_fail "Tạo site ${SITE_NAME}"
        exit 1
    fi
fi

# 4. Enable autostart
run_step "Enable autostart site" omd config "$SITE_NAME" set AUTOSTART on

# 5. Start site
run_step "Start site ${SITE_NAME}" omd start "$SITE_NAME"

# 6. Telegram notify
run_step "Cài Telegram notification" omd su "$SITE_NAME" -c "
mkdir -p ~/local/share/check_mk/notifications &&
cd ~/local/share/check_mk/notifications &&
wget --no-check-certificate -q $TELEGRAM_URL -O telegram.sh &&
chmod ug+x telegram.sh
"

# 7. Restart site
run_step "Restart site ${SITE_NAME}" omd restart "$SITE_NAME"

# 8. Final output
echo ""
echo "======================================"
echo "🎉 CHECKMK CÀI ĐẶT HOÀN TẤT"
echo "======================================"
echo "Link login : http://${IP}/${SITE_NAME}"
echo "Username   : cmkadmin"
echo "Password   : ${PASSWORD}"
echo "Log file   : ${LOG_FILE}"
echo "======================================"
