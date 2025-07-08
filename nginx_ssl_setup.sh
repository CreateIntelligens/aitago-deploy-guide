#!/bin/bash

# Aitago Nginx 設定和 SSL 憑證申請腳本
# 本腳本將設定 Nginx 反向代理並申請 SSL 憑證
# 使用方式: sudo bash nginx_ssl_setup.sh

set -e  # 遇到錯誤時立即退出

echo "=========================================="
echo "Aitago Nginx 設定和 SSL 憑證申請腳本"
echo "=========================================="

# 檢查是否以 root 權限執行
if [ "$EUID" -ne 0 ]; then
    echo "請使用 sudo 執行此腳本: sudo bash nginx_ssl_setup.sh"
    exit 1
fi

# 檢查 Nginx 是否已安裝
if ! command -v nginx &> /dev/null; then
    echo "錯誤: Nginx 未安裝，請先安裝 Nginx"
    echo "Ubuntu/Debian: sudo apt-get install nginx"
    echo "CentOS/RHEL: sudo yum install nginx"
    exit 1
fi

# 檢查 Certbot 是否已安裝
if ! command -v certbot &> /dev/null; then
    echo "錯誤: Certbot 未安裝，請先執行 server_init.sh"
    exit 1
fi

# 函數：詢問用戶輸入
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    local input
    
    if [ -n "$default_value" ]; then
        read -p "$prompt [$default_value]: " input
        input="${input:-$default_value}"
    else
        read -p "$prompt: " input
    fi
    
    eval "$var_name='$input'"
}

# 函數：詢問是否繼續
ask_continue() {
    local prompt="$1"
    local response
    
    while true; do
        read -p "$prompt (y/n): " response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "請輸入 y 或 n";;
        esac
    done
}

echo "請提供域名資訊："
echo "----------------------------------------"
ask_input "專案名稱" PROJECT_NAME
ask_input "主域名" DOMAIN
ask_input "管理員郵箱 (用於 SSL 憑證)" ADMIN_EMAIL

# 生成完整域名
MAIN_DOMAIN="${PROJECT_NAME}.${DOMAIN}"
API_DOMAIN="api.${PROJECT_NAME}.${DOMAIN}"
LINE_DOMAIN="line.${PROJECT_NAME}.${DOMAIN}"

echo ""
echo "將設定以下域名："
echo "- 主網站: $MAIN_DOMAIN"
echo "- API: $API_DOMAIN"
echo "- Line CRM: $LINE_DOMAIN"
echo ""

if ! ask_continue "是否繼續設定"; then
    echo "設定已取消"
    exit 0
fi

echo ""
echo "1. 建立 Nginx 設定檔..."
echo "----------------------------------------"
# 確保 Nginx 設定目錄存在
mkdir -p /etc/nginx/conf.d

# 建立主網站設定檔
echo "建立主網站設定檔: $MAIN_DOMAIN.conf"
cat > /etc/nginx/conf.d/$MAIN_DOMAIN.conf << EOF
server {
    listen 80;
    server_name $MAIN_DOMAIN;
    
    root /srv/aitago-web;
    index index.html index.htm;
    
    # certbot 驗證路徑
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.html?\$query_string;
    }
    
    # 靜態檔案快取設定
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# 建立 API 設定檔
echo "建立 API 設定檔: $API_DOMAIN.conf"
cat > /etc/nginx/conf.d/$API_DOMAIN.conf << EOF
upstream api {
    server 127.0.0.1:9002;
    keepalive 16;
}

server {
    listen 80;
    server_name $API_DOMAIN;

    access_log /var/log/nginx/$API_DOMAIN.access.log;
    error_log /var/log/nginx/$API_DOMAIN.error.log;

    client_max_body_size 200M;

    # 全局 CORS 設定
    set \$cors_origin '*';
    set \$cors_methods 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
    set \$cors_headers 'DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization';

    # certbot 驗證路徑
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri =404;
    }

    location / {
        if (\$request_method = OPTIONS) {
            add_header 'Access-Control-Allow-Origin' \$cors_origin always;
            add_header 'Access-Control-Allow-Methods' \$cors_methods always;
            add_header 'Access-Control-Allow-Headers' \$cors_headers always;
            add_header 'Access-Control-Allow-Credentials' 'true' always;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain charset=UTF-8';
            return 204;
        }

        proxy_pass http://api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 建立 Line CRM 設定檔
echo "建立 Line CRM 設定檔: $LINE_DOMAIN.conf"
cat > /etc/nginx/conf.d/$LINE_DOMAIN.conf << EOF
upstream linebot {
    server 127.0.0.1:9001;
    keepalive 16;
}

server {
    listen 80;
    server_name $LINE_DOMAIN;

    access_log /var/log/nginx/$LINE_DOMAIN.access.log;
    error_log /var/log/nginx/$LINE_DOMAIN.error.log;

    client_max_body_size 200M;

    # certbot 驗證路徑
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri =404;
    }

    location / {
        proxy_pass http://linebot;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Reverb WebSocket 設定
    location /reverb/ {
        proxy_pass http://127.0.0.1:8080;
        rewrite ^/reverb(/.*)\$ \$1 break;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

echo "Nginx 設定檔建立完成"

echo ""
echo "2. 建立 Certbot 驗證目錄..."
echo "----------------------------------------"
mkdir -p /var/www/certbot

echo ""
echo "3. 測試 Nginx 設定..."
echo "----------------------------------------"
echo "測試 Nginx 設定檔語法..."
if nginx -t; then
    echo "Nginx 設定檔語法正確"
else
    echo "錯誤: Nginx 設定檔語法有誤，請檢查"
    exit 1
fi

echo ""
echo "4. 重新載入 Nginx..."
echo "----------------------------------------"
systemctl reload nginx
echo "Nginx 重新載入完成"

echo ""
echo "5. 申請 SSL 憑證..."
echo "----------------------------------------"
echo "使用 Certbot 申請 SSL 憑證..."
echo "管理員郵箱: $ADMIN_EMAIL"
echo "域名: $MAIN_DOMAIN, $API_DOMAIN, $LINE_DOMAIN"
echo ""

if ask_continue "是否現在申請 SSL 憑證"; then
    echo "申請 SSL 憑證..."
    certbot --nginx \
        -d $MAIN_DOMAIN \
        -d $API_DOMAIN \
        -d $LINE_DOMAIN \
        --email $ADMIN_EMAIL \
        --agree-tos \
        --non-interactive \
        --redirect
    
    echo "SSL 憑證申請完成"
else
    echo "跳過 SSL 憑證申請"
    echo "稍後可以手動執行："
    echo "sudo certbot --nginx -d $MAIN_DOMAIN -d $API_DOMAIN -d $LINE_DOMAIN"
fi

echo ""
echo "6. 設定 SSL 憑證自動續期..."
echo "----------------------------------------"
echo "檢查 Certbot 自動續期設定..."
if systemctl list-timers | grep -q certbot; then
    echo "Certbot 自動續期已設定"
else
    echo "設定 Certbot 自動續期..."
    # 啟用 systemd timer (如果存在)
    if systemctl list-unit-files | grep -q "certbot.timer"; then
        systemctl enable certbot.timer
        systemctl start certbot.timer
        echo "Certbot systemd timer 已啟用"
    else
        # fallback 到 cron
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        echo "Certbot cron 任務已設定"
    fi
    echo "Certbot 自動續期設定完成"
fi

echo ""
echo "7. 最終重新啟動 Nginx..."
echo "----------------------------------------"
systemctl restart nginx
echo "Nginx 重新啟動完成"

echo ""
echo "8. 測試網站連接..."
echo "----------------------------------------"
echo "測試網站是否正常運作..."
sleep 5

# 測試 HTTP 連接
echo "測試 HTTP 連接..."
for domain in $MAIN_DOMAIN $API_DOMAIN $LINE_DOMAIN; do
    echo -n "測試 $domain ... "
    if curl -s -o /dev/null -w "%{http_code}" "http://$domain" > /dev/null; then
        echo "OK"
    else
        echo "Failed"
    fi
done

echo ""
echo "=========================================="
echo "Nginx 設定和 SSL 憑證申請完成！"
echo "=========================================="
echo ""
echo "設定的域名："
echo "- 主網站: https://$MAIN_DOMAIN"
echo "- API: https://$API_DOMAIN"
echo "- Line CRM: https://$LINE_DOMAIN"
echo ""
echo "Nginx 設定檔位置："
echo "- 主網站: /etc/nginx/conf.d/$MAIN_DOMAIN.conf"
echo "- API: /etc/nginx/conf.d/$API_DOMAIN.conf"
echo "- Line CRM: /etc/nginx/conf.d/$LINE_DOMAIN.conf"
echo ""
echo "SSL 憑證資訊："
echo "- 憑證位置: /etc/letsencrypt/live/$MAIN_DOMAIN/"
echo "- 自動續期: 已設定 (每日 12:00 檢查)"
echo ""
echo "管理命令："
echo "- 測試 Nginx 設定: sudo nginx -t"
echo "- 重新載入 Nginx: sudo systemctl reload nginx"
echo "- 查看 SSL 憑證: sudo certbot certificates"
echo "- 手動續期憑證: sudo certbot renew"
echo ""
echo "網站部署完成！請檢查各域名是否正常運作。"
