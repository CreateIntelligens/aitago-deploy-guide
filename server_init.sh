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
timedatectl set-timezone Asia/Taipei
timedatectl
echo "時區設定完成"

echo ""
echo "2. 安裝必要套件..."
echo "----------------------------------------"
# 1.2 安裝必要套件
echo "更新套件列表..."
apt-get update

echo "安裝必要套件: git, redis-tools, certbot, python3-certbot-nginx, mysql-client..."
apt-get install -y git redis-tools certbot python3-certbot-nginx mysql-client

echo "必要套件安裝完成"

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
docker run hello-world

echo "Docker 安裝完成"

echo "刪除驗證的 hello-world 映像..."
docker rmi hello-world
echo "hello-world 映像已刪除"

echo ""
echo "4. 建立 deploy 使用者..."
echo "----------------------------------------"
# 1.4 建立 deploy 使用者
echo "建立 deploy 使用者..."
if id "deploy" &>/dev/null; then
    echo "deploy 使用者已存在，跳過建立步驟"
else
    adduser --disabled-password --gecos "" deploy
    echo "deploy 使用者建立完成"
fi

echo "鎖定 deploy 使用者密碼..."
passwd -l deploy

echo "將 deploy 使用者加入 google-sudoers 群組..."
if getent group google-sudoers > /dev/null 2>&1; then
    usermod -aG google-sudoers deploy
    echo "deploy 使用者已加入 google-sudoers 群組"
else
    echo "警告: google-sudoers 群組不存在，跳過此步驟"
fi

echo "檢查 deploy 使用者群組..."
groups deploy

echo "建立 .ssh 資料夾並設定權限..."
mkdir -p /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

echo "deploy 使用者設定完成"

echo ""
echo "=========================================="
echo "伺服器初始化完成！"
echo "=========================================="
echo ""
echo "後續步驟："
echo "1. 複製 SSH 金鑰到 /home/deploy/.ssh/authorized_keys"
echo "2. 複製 Git SSH 私鑰到 /home/deploy/.ssh/id_rsa"
echo "3. 執行基礎設施部署 (Docker)"
echo ""
echo "請參考部署指南文件的第 2 節進行基礎設施部署"
