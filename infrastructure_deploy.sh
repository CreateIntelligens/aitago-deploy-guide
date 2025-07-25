#!/bin/bash

# Aitago 基礎設施部署腳本
# 本腳本將執行基礎設施部署 (Docker) - 文件第2節
# 使用方式: sudo bash infrastructure_deploy.sh

set -e  # 遇到錯誤時立即退出

echo "=========================================="
echo "Aitago 基礎設施部署腳本開始執行"
echo "=========================================="

# 檢查是否以 root 權限執行
if [ "$EUID" -ne 0 ]; then
    echo "請使用 sudo 執行此腳本: sudo bash infrastructure_deploy.sh"
    exit 1
fi

# 檢查 Docker 是否已安裝
if ! command -v docker &> /dev/null; then
    echo "錯誤: Docker 未安裝，請先執行 server_init.sh"
    exit 1
fi

# 檢查 Docker Compose 是否已安裝
if ! docker compose version &> /dev/null; then
    echo "錯誤: Docker Compose 未安裝，請先執行 server_init.sh"
    exit 1
fi

# 函數：詢問用戶輸入密碼
ask_password() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    local password
    
    while true; do
        if [ -n "$default_value" ]; then
            read -s -p "$prompt [$default_value]: " password
        else
            read -s -p "$prompt: " password
        fi
        echo
        
        # 如果沒有輸入且有預設值，使用預設值
        if [ -z "$password" ] && [ -n "$default_value" ]; then
            password="$default_value"
        fi
        
        if [ ${#password} -ge 8 ]; then
            eval "$var_name='$password'"
            break
        else
            echo "密碼長度至少需要 8 個字符，請重新輸入"
        fi
    done
}

echo "1. 建立資料夾結構..."
echo "----------------------------------------"
# 2.1 建立資料夾結構
echo "建立 /srv/docker-compose 相關資料夾..."
mkdir -p /srv/docker-compose/mysql
mkdir -p /srv/docker-compose/mysql-init
mkdir -p /srv/docker-compose/redis
mkdir -p /srv/docker-compose/redis-conf

echo "資料夾結構建立完成"

echo ""
echo "2. 建立 Docker 網路..."
echo "----------------------------------------"
# 2.2 建立 Docker 網路
echo "檢查 nginx-php 網路是否存在..."
if docker network ls | grep -q "nginx-php"; then
    echo "nginx-php 網路已存在，跳過建立"
else
    echo "建立 nginx-php 網路..."
    docker network create --subnet=172.21.0.0/16 --gateway=172.21.0.1 nginx-php
    echo "nginx-php 網路建立完成"
fi

echo ""
echo "3. 設定環境變數..."
echo "----------------------------------------"
# 2.3 建立環境變數檔案
echo "請設定資料庫和 Redis 密碼："
echo "注意: 密碼將用於 MySQL root 使用者和 Redis 認證"

# 詢問使用者輸入密碼
ask_password "請輸入 MySQL root 密碼 (至少8個字符-避開特殊字元($))" DB_ROOT_PASSWORD
ask_password "請輸入 Aitago 資料庫密碼" DB_AITAGO_PASSWORD "Ai3ta2go1%@"
ask_password "請輸入 Line CRM 資料庫密碼" DB_LINEBOT_PASSWORD "linebot"
ask_password "請輸入 Redis 密碼 (至少8個字符)" REDIS_PASSWORD

# 為 MySQL 建立 .env 檔案（只包含 MySQL 需要的變數）
echo "建立環境變數檔案..."
cat > /srv/docker-compose/.env << ENVEOF
DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD
ENVEOF

echo "環境變數檔案建立完成"

echo ""
echo "4. 建立 MySQL 初始化腳本..."
echo "----------------------------------------"
# 2.4 建立 MySQL 初始化腳本
echo "建立 MySQL 初始化腳本..."
cat > /srv/docker-compose/mysql-init/init.sql << SQLEOF
-- 初始化 Aitago 資料庫
CREATE DATABASE IF NOT EXISTS aitago DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'aitago'@'%' IDENTIFIED BY '$DB_AITAGO_PASSWORD';
GRANT ALL PRIVILEGES ON aitago.* TO 'aitago'@'%';
FLUSH PRIVILEGES;

-- 初始化 Line CRM 資料庫
CREATE DATABASE IF NOT EXISTS linebot DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'linebot'@'%' IDENTIFIED BY '$DB_LINEBOT_PASSWORD';
GRANT ALL PRIVILEGES ON linebot.* TO 'linebot'@'%';
FLUSH PRIVILEGES;
SQLEOF

echo "MySQL 初始化腳本建立完成"

echo ""
echo "5. 建立 Redis 設定檔..."
echo "----------------------------------------"
# 建立 Redis 設定檔，避免在 Docker Compose 中使用環境變數
echo "建立 Redis 設定檔..."
cat > /srv/docker-compose/redis-conf/redis.conf << REDISEOF
# Redis 設定檔
# Network
port 6379
bind 0.0.0.0
timeout 0
tcp-keepalive 300

# Authentication
requirepass $REDIS_PASSWORD

# General
databases 16
loglevel notice

# Persistence
save 900 1
save 300 10
save 60 10000

# Memory management
maxmemory-policy allkeys-lru
REDISEOF

echo "Redis 設定檔建立完成"

echo ""
echo "6. 建立 Docker Compose 設定檔..."
echo "----------------------------------------"
# 2.5 建立 docker-compose.yaml
echo "建立 docker-compose.yaml..."
cat > /srv/docker-compose/docker-compose.yaml << 'YAMLEOF'
services:
  mysql:
    env_file:
      - .env
    image: mysql:8.0
    container_name: mysql
    restart: unless-stopped
    tty: true
    ports:
      - '3306:3306'
    command: --bind-address=0.0.0.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_ALLOW_EMPTY_PASSWORD: 0
      TZ: 'Asia/Taipei'
    volumes:
      - ./mysql:/var/lib/mysql:rw
      - ./mysql-init:/docker-entrypoint-initdb.d:rw
    networks:
      - nginx-php
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      timeout: 20s
      retries: 10

  redis:
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - ./redis:/data:rw
      - ./redis-conf/redis.conf:/usr/local/etc/redis/redis.conf:ro
    command: redis-server /usr/local/etc/redis/redis.conf
    networks:
      - nginx-php
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      timeout: 20s
      retries: 10

networks:
    nginx-php:
        external: true
YAMLEOF

echo "Docker Compose 設定檔建立完成"

echo ""
echo "7. 啟動基礎服務..."
echo "----------------------------------------"
# 2.6 啟動基礎服務
echo "切換到 docker-compose 目錄..."
cd /srv/docker-compose

echo "下載 Docker 映像檔..."
docker compose pull

echo "啟動基礎服務 (MySQL 和 Redis)..."
docker compose up -d

echo "等待服務啟動..."
sleep 10

echo "檢查服務狀態..."
docker compose ps

echo ""
echo "8. 驗證服務..."
echo "----------------------------------------"
echo "等待 MySQL 服務完全啟動..."
timeout=60
counter=0
while ! docker exec mysql mysqladmin ping -h localhost --silent; do
    if [ $counter -ge $timeout ]; then
        echo "錯誤: MySQL 服務啟動超時"
        exit 1
    fi
    echo "等待 MySQL 服務啟動... ($counter/$timeout)"
    sleep 5
    counter=$((counter + 5))
done

echo "MySQL 服務已啟動"

echo "測試 Redis 連接..."
# 直接使用變數而不是從文件讀取
if docker exec redis redis-cli -a "$REDIS_PASSWORD" ping > /dev/null 2>&1; then
    echo "Redis 服務已啟動"
else
    echo "警告: Redis 服務可能未正常啟動"
fi

echo ""
echo "9. 設定目錄權限..."
echo "----------------------------------------"
# 設定適當的權限
chown -R 999:999 /srv/docker-compose/mysql
chown -R 999:999 /srv/docker-compose/redis
chown -R 999:999 /srv/docker-compose/redis-conf

echo "目錄權限設定完成"

echo ""
echo "=========================================="
echo "基礎設施部署完成！"
echo "=========================================="
echo ""
echo "部署的服務："
echo "- MySQL 8.0 (Port: 3306)"
echo "- Redis (Port: 6379)"
echo ""
echo "建立的資料庫："
echo "- aitago (使用者: aitago)"
echo "- linebot (使用者: linebot)"
echo ""
echo "設定檔位置："
echo "- MySQL 環境變數: /srv/docker-compose/.env"
echo "- Redis 設定檔: /srv/docker-compose/redis-conf/redis.conf"
echo ""
echo "服務狀態："
docker compose ps
echo ""
echo "後續步驟："
echo "1. 執行專案部署腳本 (建議建立 project_deploy.sh)"
echo "2. 設定 Nginx 反向代理"
echo "3. 申請 SSL 憑證"
echo ""
echo "管理命令："
echo "- 查看服務狀態: cd /srv/docker-compose && sudo docker compose ps"
echo "- 查看服務日誌: cd /srv/docker-compose && sudo docker compose logs"
echo "- 重啟服務: cd /srv/docker-compose && sudo docker compose restart"
echo "- 停止服務: cd /srv/docker-compose && sudo docker compose down"