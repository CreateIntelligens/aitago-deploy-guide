#!/bin/bash

# Aitago 完整部署腳本
# 本腳本將執行完整的 Aitago 部署流程
# 使用方式: sudo bash deploy_all.sh

set -e  # 遇到錯誤時立即退出

echo "=========================================="
echo "Aitago 完整部署腳本"
echo "=========================================="

# 檢查是否以 root 權限執行
if [ "$EUID" -ne 0 ]; then
    echo "請使用 sudo 執行此腳本: sudo bash deploy_all.sh"
    exit 1
fi

# 獲取腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# 函數：檢查腳本是否存在
check_script() {
    local script_name="$1"
    if [ ! -f "$SCRIPT_DIR/$script_name" ]; then
        echo "錯誤: 找不到腳本 $script_name"
        echo "請確保所有腳本都在同一個目錄中"
        exit 1
    fi
}

echo "Aitago 部署腳本將按以下順序執行："
echo "1. 伺服器初始化 (server_init.sh)"
echo "2. 基礎設施部署 (infrastructure_deploy.sh)"
echo "3. 專案部署 (project_deploy.sh)"
echo "4. Nginx 設定和 SSL 憑證 (nginx_ssl_setup.sh)"
echo ""
echo "注意事項："
echo "- 整個部署過程可能需要 15-30 分鐘"
echo "- 部署過程中會詢問一些設定資訊"
echo "- 請確保有穩定的網路連接"
echo "- 請確保域名 DNS 已指向此伺服器"
echo ""

if ! ask_continue "是否開始完整部署"; then
    echo "部署已取消"
    exit 0
fi

# 檢查所有必要的腳本
echo ""
echo "檢查必要的腳本檔案..."
check_script "server_init.sh"
check_script "infrastructure_deploy.sh"
check_script "project_deploy.sh"
check_script "nginx_ssl_setup.sh"
echo "所有腳本檔案都存在"

# 設定腳本權限
chmod +x "$SCRIPT_DIR/server_init.sh"
chmod +x "$SCRIPT_DIR/infrastructure_deploy.sh"
chmod +x "$SCRIPT_DIR/project_deploy.sh"
chmod +x "$SCRIPT_DIR/nginx_ssl_setup.sh"

echo ""
echo "=========================================="
echo "步驟 1: 伺服器初始化"
echo "=========================================="
if ask_continue "是否執行伺服器初始化"; then
    bash "$SCRIPT_DIR/server_init.sh"
    echo ""
    echo "伺服器初始化完成！"
else
    echo "跳過伺服器初始化"
fi

echo ""
echo "=========================================="
echo "步驟 2: 基礎設施部署"
echo "=========================================="
if ask_continue "是否執行基礎設施部署 (MySQL, Redis)"; then
    bash "$SCRIPT_DIR/infrastructure_deploy.sh"
    echo ""
    echo "基礎設施部署完成！"
else
    echo "跳過基礎設施部署"
fi

echo ""
echo "=========================================="
echo "步驟 3: 專案部署"
echo "=========================================="
if ask_continue "是否執行專案部署 (aitago-api, line-crm, aitago-web)"; then
    bash "$SCRIPT_DIR/project_deploy.sh"
    echo ""
    echo "專案部署完成！"
    echo ""
    echo "重要提醒："
    echo "- 請編輯各專案的 .env 檔案"
    echo "- 上傳前端靜態檔案到 /srv/aitago-web"
    echo "- 啟動專案容器: /srv/manage_projects.sh start all"
    echo ""
    if ask_continue "是否現在啟動所有專案容器"; then
        echo "啟動專案容器..."
        /srv/manage_projects.sh start all
        echo "專案容器啟動完成"
    else
        echo "請稍後手動啟動專案容器"
    fi
else
    echo "跳過專案部署"
fi

echo ""
echo "=========================================="
echo "步驟 4: Nginx 設定和 SSL 憑證"
echo "=========================================="
if ask_continue "是否執行 Nginx 設定和 SSL 憑證申請"; then
    bash "$SCRIPT_DIR/nginx_ssl_setup.sh"
    echo ""
    echo "Nginx 設定和 SSL 憑證申請完成！"
else
    echo "跳過 Nginx 設定和 SSL 憑證申請"
fi

echo ""
echo "=========================================="
echo "部署完成！"
echo "=========================================="
echo ""
echo "部署摘要："
echo "- 伺服器已初始化"
echo "- 基礎設施 (MySQL, Redis) 已部署"
echo "- 專案 (aitago-api, line-crm, aitago-web) 已設定"
echo "- Nginx 反向代理已設定"
echo "- SSL 憑證已申請"
echo ""
echo "後續檢查項目："
echo "1. 檢查專案容器狀態: /srv/manage_projects.sh status all"
echo "2. 檢查 Nginx 狀態: sudo systemctl status nginx"
echo "3. 檢查網站是否正常運作"
echo "4. 檢查 SSL 憑證是否正常"
echo ""
echo "常用管理命令："
echo "- 專案管理: /srv/manage_projects.sh [start|stop|restart|status] [api|crm|all]"
echo "- 查看基礎設施: cd /srv/docker-compose && sudo docker compose ps"
echo "- 重新載入 Nginx: sudo systemctl reload nginx"
echo "- 查看 SSL 憑證: sudo certbot certificates"
echo ""
echo "如果遇到問題，請查看相關日誌："
echo "- 專案日誌: /srv/manage_projects.sh logs [api|crm]"
echo "- Nginx 日誌: sudo tail -f /var/log/nginx/*.log"
echo "- 系統日誌: sudo journalctl -u nginx"
echo ""
echo "部署完成！祝您使用愉快！"
