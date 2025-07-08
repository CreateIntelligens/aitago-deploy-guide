#!/bin/bash

# Aitago 伺服器初始化腳本
# 本腳本將執行伺服器初始化的步驟 1-3
# 使用方式: sudo bash server_init.sh

set -e  # 遇到錯誤時立即退出

echo "=========================================="
echo "Aitago 伺服器初始化腳本開始執行"
echo "=========================================="

# 檢查是否以 root 權限執行
if [ "$EUID" -ne 0 ]; then
    echo "請使用 sudo 執行此腳本: sudo bash server_init.sh"
    exit 1
fi

echo "1. 系統設定..."
echo "----------------------------------------"
# 1.1 系統設定
echo "設定時區為 Asia/Taipei..."
if timedatectl set-timezone Asia/Taipei; then
    echo "✓ 時區設定完成"
    timedatectl status | grep "Time zone"
else
    echo "✗ 時區設定失敗"
    exit 1
fi

echo ""
echo "2. 安裝必要套件..."
echo "----------------------------------------"
# 1.2 安裝必要套件
echo "更新套件列表..."
if apt-get update; then
    echo "✓ 套件列表更新完成"
else
    echo "✗ 套件列表更新失敗"
    exit 1
fi

echo "安裝必要套件: git, redis-tools, certbot, python3-certbot-nginx, mysql-client..."
if apt-get install -y git redis-tools certbot python3-certbot-nginx mysql-client; then
    echo "✓ 必要套件安裝完成"
else
    echo "✗ 必要套件安裝失敗"
    exit 1
fi

echo ""
echo "3. 安裝 Docker..."
echo "----------------------------------------"
# 1.3 安裝 Docker
echo "安裝 Docker 相依套件..."
apt-get install -y ca-certificates curl

echo "建立 Docker GPG 金鑰目錄..."
install -m 0755 -d /etc/apt/keyrings

echo "下載 Docker GPG 金鑰..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "新增 Docker 儲存庫..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "更新套件列表..."
apt-get update

echo "安裝 Docker 相關套件..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "驗證 Docker 安裝..."
if docker run hello-world; then
    echo "✓ Docker 安裝驗證成功"
    echo "清理驗證用的 hello-world 映像..."
    docker rmi hello-world
    echo "✓ hello-world 映像已清理"
else
    echo "✗ Docker 安裝驗證失敗"
    exit 1
fi

echo "✓ Docker 安裝完成"

echo ""
echo "4. 建立 deploy 使用者..."
echo "----------------------------------------"
# 1.4 建立 deploy 使用者
echo "建立 deploy 使用者..."
if id "deploy" &>/dev/null; then
    echo "✓ deploy 使用者已存在，跳過建立步驟"
else
    if adduser --disabled-password --gecos "" deploy; then
        echo "✓ deploy 使用者建立完成"
    else
        echo "✗ deploy 使用者建立失敗"
        exit 1
    fi
fi

echo "鎖定 deploy 使用者密碼..."
passwd -l deploy

echo "將 deploy 使用者加入 google-sudoers 群組..."
if getent group google-sudoers > /dev/null 2>&1; then
    usermod -aG google-sudoers deploy
    echo "✓ deploy 使用者已加入 google-sudoers 群組"
else
    echo "⚠ 警告: google-sudoers 群組不存在，跳過此步驟"
fi

echo "檢查 deploy 使用者群組..."
groups deploy

echo "建立 .ssh 資料夾並設定基本權限..."
if mkdir -p /home/deploy/.ssh && touch /home/deploy/.ssh/authorized_keys; then
    chown -R deploy:deploy /home/deploy/.ssh
    chmod 700 /home/deploy/.ssh
    chmod 600 /home/deploy/.ssh/authorized_keys
    echo "✓ .ssh 資料夾和基本權限設定完成"
else
    echo "✗ .ssh 資料夾設定失敗"
    exit 1
fi

echo ""
echo "設定 deploy 使用者的 SSH 金鑰..."
echo "從 GCP Secret Manager 獲取 SSH 設定..."

# 檢查是否安裝了 gcloud CLI
if command -v gcloud &> /dev/null; then
    echo "檢測到 gcloud CLI，嘗試從 GCP Secret Manager 獲取 SSH 設定..."
    
    # 從 GCP Secret Manager 複製 SSH 設定
    if gcloud secrets versions access latest --secret=server-user-deploy --project=wonderland-nft > /tmp/deploy_secret.txt 2>/dev/null; then
        echo "成功獲取 Secret Manager 內容"
        
        # 提取 AUTHORIZED_KEY 值（處理多行格式）
        echo "設定 authorized_keys..."
        if sed -n '/AUTHORIZED_KEY="/,/"$/p' /tmp/deploy_secret.txt | sed '1s/AUTHORIZED_KEY="//; $s/"$//; 1{/^$/d}' > /home/deploy/.ssh/authorized_keys; then
            echo "✓ authorized_keys 設定完成"
        else
            echo "✗ authorized_keys 設定失敗"
        fi
        
        # 提取 GITLAB_RSA 值（處理多行格式）
        echo "設定 GitLab SSH 私鑰..."
        if sed -n '/GITLAB_RSA="/,/"$/p' /tmp/deploy_secret.txt | sed '1s/GITLAB_RSA="//; $s/"$//; 1{/^$/d}' > /home/deploy/.ssh/id_rsa; then
            echo "✓ GitLab SSH 私鑰設定完成"
        else
            echo "✗ GitLab SSH 私鑰設定失敗"
        fi
        
        # 清理臨時檔案
        rm -f /tmp/deploy_secret.txt
        
        # 重新設定權限（確保從 Secret Manager 載入的內容有正確權限）
        chmod 600 /home/deploy/.ssh/authorized_keys
        chmod 600 /home/deploy/.ssh/id_rsa
        chown deploy:deploy /home/deploy/.ssh/authorized_keys
        chown deploy:deploy /home/deploy/.ssh/id_rsa
        
        echo "✓ SSH 金鑰設定完成（來自 GCP Secret Manager）"
    else
        echo "⚠ 警告: 無法從 GCP Secret Manager 獲取 SSH 設定"
        echo "  請檢查 GCP 權限或手動設定 SSH 金鑰"
    fi
else
    echo "⚠ 警告: 未檢測到 gcloud CLI"
    echo "  請安裝 gcloud CLI 或手動設定 SSH 金鑰"
fi

echo ""
echo "手動設定說明："
echo "如果自動設定失敗，請手動執行以下步驟："
echo "1. 複製 SSH 公鑰到 /home/deploy/.ssh/authorized_keys"
echo "2. 複製 GitLab SSH 私鑰到 /home/deploy/.ssh/id_rsa"
echo "3. 設定權限: chmod 600 /home/deploy/.ssh/{authorized_keys,id_rsa}"
echo "4. 設定擁有者: chown deploy:deploy /home/deploy/.ssh/{authorized_keys,id_rsa}"

echo "deploy 使用者設定完成"

echo ""
echo "=========================================="
echo "伺服器初始化完成！"
echo "=========================================="
echo ""
echo "後續步驟："
echo "1. 如果 SSH 金鑰設定失敗，請手動設定 SSH 金鑰"
echo "2. 執行基礎設施部署 (Docker)"
echo ""
echo "請參考部署指南文件的第 2 節進行基礎設施部署"
