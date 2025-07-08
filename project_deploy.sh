#!/bin/bash

# Aitago 專案部署腳本
# 本腳本將執行三個專案的部署 (aitago-api, line-crm, aitago-web)
# 使用方式: sudo bash project_deploy.sh

set -e  # 遇到錯誤時立即退出

echo "=========================================="
echo "Aitago 專案部署腳本開始執行"
echo "=========================================="

# 檢查是否以 root 權限執行
if [ "$EUID" -ne 0 ]; then
    echo "請使用 sudo 執行此腳本: sudo bash project_deploy.sh"
    exit 1
fi

# 檢查 Docker 是否已安裝
if ! command -v docker &> /dev/null; then
    echo "錯誤: Docker 未安裝，請先執行 server_init.sh"
    exit 1
fi

# 檢查 nginx-php 網路是否存在
if ! docker network ls | grep -q "nginx-php"; then
    echo "錯誤: nginx-php 網路不存在，請先執行 infrastructure_deploy.sh"
    exit 1
fi

# 檢查 deploy 使用者是否存在
if ! id "deploy" &>/dev/null; then
    echo "錯誤: deploy 使用者不存在，請先執行 server_init.sh"
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

echo "專案部署前準備..."
echo "----------------------------------------"
echo "本腳本將部署以下三個專案："
echo "1. aitago-api (後端 API)"
echo "2. line-crm (Line CRM 系統)"
echo "3. aitago-web (前端網站)"
echo ""

# 詢問 Git 儲存庫資訊
echo "請提供 Git 儲存庫資訊："
ask_input "aitago-api Git 儲存庫 URL" AITAGO_API_REPO "git@gitlab.aicreate360.com:aitago/aitago-api.git"
ask_input "line-crm Git 儲存庫 URL" LINE_CRM_REPO "git@gitlab.aicreate360.com:aitago/line-crm.git"
ask_input "VITE_API_URL (用於 line-crm 建置)" VITE_API_URL "https://api.example.com"

echo ""
echo "請提供專案基本設定："
ask_input "專案域名 (例: example.com)" PROJECT_DOMAIN
ask_input "專案名稱 (例: aitago)" PROJECT_NAME_INPUT
ask_input "Redis 密碼" REDIS_PASSWORD_INPUT
ask_input "Aitago 資料庫密碼" DB_AITAGO_PASSWORD "Ai3ta2go1%@"
ask_input "Line CRM 資料庫密碼" DB_LINEBOT_PASSWORD "linebot"

echo ""
if ! ask_continue "是否開始部署"; then
    echo "部署已取消"
    exit 0
fi

echo ""
echo "1. 部署 aitago-api (後端)..."
echo "----------------------------------------"
# 3.1 部署 aitago-api
echo "建立 aitago-api 專案資料夾..."
cd /srv
mkdir -p aitago-api
chown deploy:deploy aitago-api

echo "克隆 aitago-api 專案..."
sudo -u deploy bash -c "cd /srv/aitago-api && git clone '$AITAGO_API_REPO' ./src"

echo "建立 aitago-api 的 docker-compose.yaml..."
cat > /srv/aitago-api/docker-compose.yaml << 'EOF'
services:
  aitago-api:
    build:
        context: ./src
        dockerfile: Dockerfile
    image: aitago-api:latest
    container_name: aitago-api
    ports:
        - "9002:9000"
    volumes:
     - ./src:/var/www/html:rw
    restart: always
    networks:
      - nginx-php
    
networks:
  nginx-php:
    external: true
EOF

echo "建立 aitago-api 的 .env 檔案..."
cd /srv/aitago-api/src
if [ -f ".env.example" ]; then
    cp .env.example .env
    chown deploy:deploy .env
    echo "已複製 .env.example 到 .env"
    
    # 自動產生 APP_KEY 和 JWT_SECRET
    echo "自動產生 APP_KEY 和 JWT_SECRET..."
    APP_KEY=$(openssl rand -base64 32)
    JWT_SECRET=$(openssl rand -base64 64)
    
    # 詢問 Mail 設定
    echo "請提供 Mail 設定資訊："
    ask_input "Mail 使用者名稱" MAIL_USERNAME "bobbyliou830228@gmail.com"
    ask_input "Mail 密碼" MAIL_PASSWORD "mrza haad cxcr uari"
    
    # 更新 .env 檔案中的設定
    sed -i "s/APP_KEY=.*/APP_KEY=base64:$APP_KEY/" .env
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
    
    # 添加或更新 APP_TIMEZONE 設定
    if grep -q "^APP_TIMEZONE=" .env; then
        sed -i "s/APP_TIMEZONE=.*/APP_TIMEZONE=Asia\/Taipei/" .env
    else
        echo "APP_TIMEZONE=Asia/Taipei" >> .env
    fi
    
    # 添加或更新 JWT 相關設定 (使用 grep 檢查是否存在，不存在則添加)
    if grep -q "^JWT_TTL=" .env; then
        sed -i "s/JWT_TTL=.*/JWT_TTL=99999999999/" .env
    else
        echo "JWT_TTL=99999999999" >> .env
    fi
    
    if grep -q "^JWT_REFRESH_TTL=" .env; then
        sed -i "s/JWT_REFRESH_TTL=.*/JWT_REFRESH_TTL=99999999999/" .env
    else
        echo "JWT_REFRESH_TTL=99999999999" >> .env
    fi
    
    if grep -q "^JWT_ALGO=" .env; then
        sed -i "s/JWT_ALGO=.*/JWT_ALGO=HS256/" .env
    else
        echo "JWT_ALGO=HS256" >> .env
    fi
    
    sed -i "s|APP_URL=.*|APP_URL=https://api.$PROJECT_NAME_INPUT.$PROJECT_DOMAIN|" .env
    sed -i "s|LINE_CRM_URL=.*|LINE_CRM_URL=https://line.$PROJECT_NAME_INPUT.$PROJECT_DOMAIN|" .env
    sed -i "s|CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=https://$PROJECT_NAME_INPUT.$PROJECT_DOMAIN|" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_AITAGO_PASSWORD|" .env
    sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD_INPUT|" .env
    sed -i "s|MAIL_USERNAME=.*|MAIL_USERNAME=$MAIL_USERNAME|" .env
    sed -i "s|MAIL_PASSWORD=.*|MAIL_PASSWORD=$MAIL_PASSWORD|" .env
    sed -i "s|FRONT_END_URL=.*|FRONT_END_URL=https://$PROJECT_NAME_INPUT.$PROJECT_DOMAIN|" .env
    
    echo "aitago-api .env 檔案已自動設定完成"
    echo "生成的 JWT_SECRET: $JWT_SECRET (將用於 line-crm)"
else
    echo "警告: .env.example 檔案不存在，請手動建立 .env 檔案"
fi

echo "aitago-api 專案設定完成"

echo ""
echo "2. 部署 line-crm (Line CRM)..."
echo "----------------------------------------"
# 3.2 部署 line-crm
echo "建立 line-crm 專案資料夾..."
cd /srv
mkdir -p line-crm
chown deploy:deploy line-crm

echo "克隆 line-crm 專案..."
sudo -u deploy bash -c "cd /srv/line-crm && git clone '$LINE_CRM_REPO' ./src"

echo "建立 line-crm 的 docker-compose.yaml..."
cat > /srv/line-crm/docker-compose.yaml << EOF
services:
  linebot:
    build:
        context: ./src
        dockerfile: Dockerfile
        args:
          - VITE_API_URL=$VITE_API_URL
    image: linebot:latest
    container_name: linebot
    ports:
        - "9001:80"
    restart: always
    networks:
      - nginx-php

  reverb-server:
    image: linebot:latest
    container_name: reverb-server
    command: php artisan reverb:start
    ports:
      - "8080:8080"
    restart: always
    depends_on:
      - linebot
    networks:
      - nginx-php
    
networks:
  nginx-php:
    external: true
EOF

echo "建立 line-crm 的 .env 檔案..."
cd /srv/line-crm/src
if [ -f ".env.example" ]; then
    cp .env.example .env
    chown deploy:deploy .env
    echo "已複製 .env.example 到 .env"
    
    # 自動產生 APP_KEY (使用相同的 JWT_SECRET)
    echo "自動產生 APP_KEY..."
    LINE_APP_KEY=$(openssl rand -base64 32)
    
    # 更新 .env 檔案中的設定
    sed -i "s/APP_KEY=.*/APP_KEY=base64:$LINE_APP_KEY/" .env
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
    
    # 添加或更新 APP_TIMEZONE 設定
    if grep -q "^APP_TIMEZONE=" .env; then
        sed -i "s/APP_TIMEZONE=.*/APP_TIMEZONE=Asia\/Taipei/" .env
    else
        echo "APP_TIMEZONE=Asia/Taipei" >> .env
    fi
    
    # 添加或更新 JWT 相關設定 (使用 grep 檢查是否存在，不存在則添加)
    if grep -q "^JWT_TTL=" .env; then
        sed -i "s/JWT_TTL=.*/JWT_TTL=99999999999/" .env
    else
        echo "JWT_TTL=99999999999" >> .env
    fi
    
    if grep -q "^JWT_REFRESH_TTL=" .env; then
        sed -i "s/JWT_REFRESH_TTL=.*/JWT_REFRESH_TTL=99999999999/" .env
    else
        echo "JWT_REFRESH_TTL=99999999999" >> .env
    fi
    
    if grep -q "^JWT_ALGO=" .env; then
        sed -i "s/JWT_ALGO=.*/JWT_ALGO=HS256/" .env
    else
        echo "JWT_ALGO=HS256" >> .env
    fi
    
    # 詢問 Line 相關設定
    echo "請提供 Line 相關設定資訊："
    ask_input "Line Bot Channel Basic ID" LINE_BOT_CHANNEL_BASIC_ID
    ask_input "Line Bot Channel Access Token" LINE_BOT_CHANNEL_ACCESS_TOKEN
    ask_input "Line Bot Channel ID" LINE_BOT_CHANNEL_ID
    ask_input "Line Bot Channel Secret" LINE_BOT_CHANNEL_SECRET
    ask_input "Line Login Channel ID" LINE_LOGIN_CHANNEL_ID
    ask_input "Line Login Channel Secret" LINE_LOGIN_CHANNEL_SECRET
    ask_input "Google Cloud Storage Path Prefix" GOOGLE_CLOUD_STORAGE_PATH_PREFIX "$PROJECT_NAME_INPUT"
    
    # 更新 .env 檔案
    sed -i "s|APP_URL=.*|APP_URL=https://line.$PROJECT_NAME_INPUT.$PROJECT_DOMAIN|" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_LINEBOT_PASSWORD|" .env
    sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD_INPUT|" .env
    sed -i "s|LINE_BOT_CHANNEL_BASIC_ID=.*|LINE_BOT_CHANNEL_BASIC_ID=$LINE_BOT_CHANNEL_BASIC_ID|" .env
    sed -i "s|LINE_BOT_CHANNEL_ACCESS_TOKEN=.*|LINE_BOT_CHANNEL_ACCESS_TOKEN=$LINE_BOT_CHANNEL_ACCESS_TOKEN|" .env
    sed -i "s|LINE_BOT_CHANNEL_ID=.*|LINE_BOT_CHANNEL_ID=$LINE_BOT_CHANNEL_ID|" .env
    sed -i "s|LINE_BOT_CHANNEL_SECRET=.*|LINE_BOT_CHANNEL_SECRET=$LINE_BOT_CHANNEL_SECRET|" .env
    sed -i "s|LINE_LOGIN_CHANNEL_ID=.*|LINE_LOGIN_CHANNEL_ID=$LINE_LOGIN_CHANNEL_ID|" .env
    sed -i "s|LINE_LOGIN_CHANNEL_SECRET=.*|LINE_LOGIN_CHANNEL_SECRET=$LINE_LOGIN_CHANNEL_SECRET|" .env
    sed -i "s|GOOGLE_CLOUD_STORAGE_PATH_PREFIX=.*|GOOGLE_CLOUD_STORAGE_PATH_PREFIX=\"$GOOGLE_CLOUD_STORAGE_PATH_PREFIX\"|" .env
    
    echo "line-crm .env 檔案已自動設定完成"
    echo ""
    echo "重要提醒："
    echo "- 請手動上傳 GCS key 檔案到 /srv/line-crm/src/storage/app/ 目錄"
    echo "- 檔案名稱: gcp_storage_api_key.json"
else
    echo "警告: .env.example 檔案不存在，請手動建立 .env 檔案"
fi

echo "line-crm 專案設定完成"

echo ""
echo "3. 部署 aitago-web (前端)..."
echo "----------------------------------------"
# 3.3 部署 aitago-web
echo "建立 aitago-web 專案資料夾..."
cd /srv
mkdir -p aitago-web
chown -R deploy:deploy aitago-web
find aitago-web -type d -exec chmod 2775 {} \;
chmod -R 774 aitago-web

echo "aitago-web 資料夾建立完成"
echo "注意: 需要手動上傳打包好的前端靜態檔案到 /srv/aitago-web 目錄"

echo ""
echo "4. 建立專案管理腳本..."
echo "----------------------------------------"
# 建立專案管理腳本
cat > /srv/manage_projects.sh << 'EOF'
#!/bin/bash

# Aitago 專案管理腳本
# 用於管理三個專案的 Docker 容器

set -e

show_help() {
    echo "Aitago 專案管理腳本"
    echo ""
    echo "用法: $0 [COMMAND] [PROJECT]"
    echo ""
    echo "Commands:"
    echo "  start     啟動專案"
    echo "  stop      停止專案"
    echo "  restart   重啟專案"
    echo "  status    查看專案狀態"
    echo "  logs      查看專案日誌"
    echo "  build     重新建置專案"
    echo "  update    更新專案代碼並重新建置"
    echo ""
    echo "Projects:"
    echo "  api       aitago-api"
    echo "  line      line-crm"
    echo "  all       所有專案"
    echo ""
    echo "Examples:"
    echo "  $0 start all"
    echo "  $0 restart api"
    echo "  $0 logs line"
}

COMMAND=$1
PROJECT=$2

if [ -z "$COMMAND" ] || [ -z "$PROJECT" ]; then
    show_help
    exit 1
fi

case $PROJECT in
    api)
        PROJECT_DIR="/srv/aitago-api"
        ;;
    crm)
        PROJECT_DIR="/srv/line-crm"
        ;;
    all)
        PROJECT_DIR="all"
        ;;
    *)
        echo "錯誤: 未知的專案 '$PROJECT'"
        show_help
        exit 1
        ;;
esac

execute_command() {
    local dir=$1
    local cmd=$2
    
    echo "在 $dir 執行: $cmd"
    cd "$dir"
    eval "$cmd"
}

case $COMMAND in
    start)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "docker compose up -d"
            execute_command "/srv/line-crm" "docker compose up -d"
        else
            execute_command "$PROJECT_DIR" "docker compose up -d"
        fi
        ;;
    stop)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "docker compose down"
            execute_command "/srv/line-crm" "docker compose down"
        else
            execute_command "$PROJECT_DIR" "docker compose down"
        fi
        ;;
    restart)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "docker compose restart"
            execute_command "/srv/line-crm" "docker compose restart"
        else
            execute_command "$PROJECT_DIR" "docker compose restart"
        fi
        ;;
    status)
        if [ "$PROJECT" = "all" ]; then
            echo "=== aitago-api 狀態 ==="
            execute_command "/srv/aitago-api" "docker compose ps"
            echo ""
            echo "=== line-crm 狀態 ==="
            execute_command "/srv/line-crm" "docker compose ps"
        else
            execute_command "$PROJECT_DIR" "docker compose ps"
        fi
        ;;
    logs)
        if [ "$PROJECT" = "all" ]; then
            echo "請指定特定專案查看日誌"
            exit 1
        else
            execute_command "$PROJECT_DIR" "docker compose logs -f"
        fi
        ;;
    build)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "docker compose up -d --build"
            execute_command "/srv/line-crm" "docker compose up -d --build"
        else
            execute_command "$PROJECT_DIR" "docker compose up -d --build"
        fi
        echo "清理未使用的 Docker 映像..."
        docker image prune -f
        ;;
    update)
        if [ "$PROJECT" = "all" ]; then
            echo "=== 更新 aitago-api ==="
            execute_command "/srv/aitago-api/src" "sudo -u deploy git pull"
            execute_command "/srv/aitago-api" "docker compose up -d --build"
            echo ""
            echo "=== 更新 line-crm ==="
            execute_command "/srv/line-crm/src" "sudo -u deploy git pull"
            execute_command "/srv/line-crm" "docker compose up -d --build"
        else
            if [ "$PROJECT" = "api" ]; then
                execute_command "/srv/aitago-api/src" "sudo -u deploy git pull"
            elif [ "$PROJECT" = "crm" ]; then
                execute_command "/srv/line-crm/src" "sudo -u deploy git pull"
            fi
            execute_command "$PROJECT_DIR" "docker compose up -d --build"
        fi
        echo "清理未使用的 Docker 映像..."
        docker image prune -f
        ;;
    *)
        echo "錯誤: 未知的命令 '$COMMAND'"
        show_help
        exit 1
        ;;
esac

echo "命令執行完成"
EOF

chmod +x /srv/manage_projects.sh

echo "專案管理腳本已建立: /srv/manage_projects.sh"

echo ""
echo "=========================================="
echo "專案部署設定完成！"
echo "=========================================="
echo ""
echo "部署的專案："
echo "- aitago-api: /srv/aitago-api (Port: 9002)"
echo "- line-crm: /srv/line-crm (Port: 9001, 8080)"
echo "- aitago-web: /srv/aitago-web (靜態檔案)"
echo ""
echo "後續步驟："
echo "1. 編輯各專案的 .env 檔案設定"
echo "2. 啟動專案容器:"
echo "   - 啟動 aitago-api: /srv/manage_projects.sh start api"
echo "   - 啟動 line-crm: /srv/manage_projects.sh start crm"
echo "   - 啟動所有專案: /srv/manage_projects.sh start all"
echo "3. 上傳前端靜態檔案到 /srv/aitago-web"
echo "4. 設定 Nginx 反向代理"
echo "5. 申請 SSL 憑證"
echo ""
echo "專案管理命令："
echo "- 查看狀態: /srv/manage_projects.sh status all"
echo "- 重新建置: /srv/manage_projects.sh build all"
echo "- 更新代碼: /srv/manage_projects.sh update all"
echo "- 查看日誌: /srv/manage_projects.sh logs api"
echo ""
echo "重要提醒："
echo "- 請先編輯 .env 檔案再啟動專案"
echo "- 確保資料庫連接資訊正確"
echo "- 前端檔案需要手動上傳"
