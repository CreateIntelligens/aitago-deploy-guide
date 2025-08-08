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

# 函數：驗證輸入是否包含不安全字符
validate_input() {
    local value="$1"
    local field_name="$2"
    
    # 檢查是否包含 | 字符（我們的 sed 分隔符）
    if [[ "$value" == *"|"* ]]; then
        echo "錯誤: $field_name 不能包含 '|' 字符"
        return 1
    fi
    
    # 檢查是否包含換行符
    if [[ "$value" == *$'\n'* ]]; then
        echo "錯誤: $field_name 不能包含換行符"
        return 1
    fi
    
    return 0
}

# 函數：安全地更新或添加環境變數到 .env 檔案（保持原位置）
update_or_add_env_var() {
    local env_file="$1"
    local var_name="$2"
    local var_value="$3"
    local description="${4:-$var_name}"
    
    # 檢查 .env 檔案是否存在
    if [ ! -f "$env_file" ]; then
        echo "錯誤: $env_file 檔案不存在"
        return 1
    fi
    
    # 檢查值是否已經有雙引號包圍，如果沒有則添加
    local quoted_value="$var_value"
    if [[ ! "$var_value" =~ ^\".*\"$ ]]; then
        quoted_value="\"$var_value\""
    fi
    
    # 轉義特殊字符以避免 sed 命令出錯
    local escaped_value=$(printf '%s\n' "$quoted_value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # 檢查變數是否已存在
    if grep -q "^${var_name}=" "$env_file"; then
        echo "更新現有的 $description..."
        # 使用 sed 在原位置更新變數
        sed -i "s|^${var_name}=.*|${var_name}=${escaped_value}|" "$env_file"
        echo "已更新 $description"
    else
        echo "添加新的 $description..."
        printf "%s=%s
" "$var_name" "$quoted_value" >> "$env_file"
        echo "已添加 $description"
    fi
}

# 函數：詢問用戶輸入（帶驗證）
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    local input
    
    while true; do
        if [ -n "$default_value" ]; then
            read -p "$prompt [$default_value]: " input
            input="${input:-$default_value}"
        else
            read -p "$prompt: " input
        fi
        
        # 驗證輸入
        if validate_input "$input" "$prompt"; then
            eval "$var_name='$input'"
            break
        else
            echo "請重新輸入，避免使用 '|' 字符和換行符"
        fi
    done
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

# 函數：選項選擇器
ask_choice() {
    local prompt="$1"
    local var_name="$2"
    local default_index="$3"
    shift 3
    local options=("$@")
    local choice
    
    while true; do
        echo "$prompt"
        for i in "${!options[@]}"; do
            local index=$((i + 1))
            if [ "$index" -eq "$default_index" ]; then
                echo "$index) ${options[$i]} (預設)"
            else
                echo "$index) ${options[$i]}"
            fi
        done
        
        read -p "請輸入選項 (1-${#options[@]}) [預設: $default_index]: " choice
        choice="${choice:-$default_index}"
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            local selected_option="${options[$((choice - 1))]}"
            local value=$(echo "$selected_option" | cut -d'(' -f1 | xargs)
            eval "$var_name='$value'"
            echo "已選擇：$selected_option"
            break
        else
            echo "無效的選項，請輸入 1-${#options[@]} 之間的數字"
        fi
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
ask_choice "請選擇要部署的分支：" GIT_BRANCH 2 "main (主分支)" "develop (開發分支)"
ask_input "VITE_API_URL (用於 line-crm 建置，要填寫line-crm的 API URL)" VITE_API_URL "https://api.example.com"

echo ""
echo "請提供專案基本設定："
ask_input "專案域名 (例: example.com)" PROJECT_DOMAIN
ask_input "專案名稱 (例: aitago)" PROJECT_NAME_INPUT
ask_choice "請選擇應用程式環境：" APP_ENV 1 "local (開發環境)" "production (生產環境)"
ask_input "Redis 密碼" REDIS_PASSWORD_INPUT
ask_input "Aitago 資料庫密碼" DB_AITAGO_PASSWORD "Ai3ta2go1"
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

echo "克隆 aitago-api 專案 ($GIT_BRANCH 分支)..."
sudo -u deploy bash -c "cd /srv/aitago-api && git clone -b '$GIT_BRANCH' '$AITAGO_API_REPO' ./src"

echo "建立 aitago-api 的 docker-compose.yaml..."
cat > /srv/aitago-api/docker-compose.yaml << 'EOF'
services:
  aitago-api:
    build:
        context: ./src
        dockerfile: Dockerfile
    image: aitago-api:latest
    container_name: aitago-api
    restart: unless-stopped
    ports:
        - "9002:80"
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
    JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
    
    # 詢問 Mail 設定
    echo "請提供 Mail 設定資訊："
    ask_input "Mail 主機 (SMTP)" MAIL_HOST "smtp.gmail.com"
    ask_input "Mail 埠號 (SMTP)" MAIL_PORT "587"
    ask_input "Mail 使用者名稱" MAIL_USERNAME "mis@aicreate360.com"
    ask_input "Mail 密碼" MAIL_PASSWORD "\"fwiq qspy bhfc oirc\""
    ask_input "Mail 發送地址" MAIL_FROM_ADDRESS "service@aitago.tw"
    
    # 更新 .env 檔案中的設定
    update_or_add_env_var ".env" "APP_KEY" "base64:$APP_KEY" "APP_KEY"
    
    # 使用新的函數安全地處理 JWT_SECRET
    update_or_add_env_var ".env" "JWT_SECRET" "$JWT_SECRET" "JWT_SECRET"
    
    # 添加或更新 APP_TIMEZONE 設定
    update_or_add_env_var ".env" "APP_TIMEZONE" "Asia/Taipei" "APP_TIMEZONE"
    
    # 確保 .env 文件以換行符結尾，避免新設定接在最後一行後面
    if [ -s .env ] && [ "$(tail -c1 .env | wc -l)" -eq 0 ]; then
        echo "" >> .env
    fi
    
    # 添加或更新 JWT 相關設定
    update_or_add_env_var ".env" "JWT_TTL" "99999999999" "JWT_TTL"
    update_or_add_env_var ".env" "JWT_REFRESH_TTL" "99999999999" "JWT_REFRESH_TTL"
    update_or_add_env_var ".env" "JWT_ALGO" "HS256" "JWT_ALGO"
    
    # 添加或更新 APP_ENV 設定
    update_or_add_env_var ".env" "APP_ENV" "$APP_ENV" "APP_ENV"
    
    # 更新其他環境變數
    update_or_add_env_var ".env" "APP_URL" "https://api.$PROJECT_NAME_INPUT.$PROJECT_DOMAIN" "APP_URL"
    update_or_add_env_var ".env" "LINE_CRM_URL" "https://line.$PROJECT_NAME_INPUT.$PROJECT_DOMAIN" "LINE_CRM_URL"
    update_or_add_env_var ".env" "CORS_ALLOWED_ORIGINS" "https://$PROJECT_NAME_INPUT.$PROJECT_DOMAIN" "CORS_ALLOWED_ORIGINS"
    update_or_add_env_var ".env" "DB_CONNECTION" "mysql" "DB_CONNECTION"
    update_or_add_env_var ".env" "DB_HOST" "172.21.0.1" "DB_HOST"
    update_or_add_env_var ".env" "DB_PASSWORD" "$DB_AITAGO_PASSWORD" "DB_PASSWORD"
    update_or_add_env_var ".env" "REDIS_PASSWORD" "$REDIS_PASSWORD_INPUT" "REDIS_PASSWORD"
    update_or_add_env_var ".env" "REDIS_HOST" "172.21.0.1" "REDIS_HOST"
    update_or_add_env_var ".env" "MAIL_MAILER" "smtp" "MAIL_MAILER"
    update_or_add_env_var ".env" "MAIL_HOST" "$MAIL_HOST" "MAIL_HOST"
    update_or_add_env_var ".env" "MAIL_PORT" "$MAIL_PORT" "MAIL_PORT"
    update_or_add_env_var ".env" "MAIL_USERNAME" "$MAIL_USERNAME" "MAIL_USERNAME"
    update_or_add_env_var ".env" "MAIL_PASSWORD" "$MAIL_PASSWORD" "MAIL_PASSWORD"
    update_or_add_env_var ".env" "MAIL_FROM_ADDRESS" "$MAIL_FROM_ADDRESS" "MAIL_FROM_ADDRESS"
    update_or_add_env_var ".env" "FRONT_END_URL" "https://$PROJECT_NAME_INPUT.$PROJECT_DOMAIN" "FRONT_END_URL"
    
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

echo "克隆 line-crm 專案 ($GIT_BRANCH 分支)..."
sudo -u deploy bash -c "cd /srv/line-crm && git clone -b '$GIT_BRANCH' '$LINE_CRM_REPO' ./src"

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
    restart: unless-stopped
    ports:
        - "9001:80"
    networks:
      - nginx-php

  reverb-server:
    image: linebot:latest
    container_name: reverb-server
    command: php artisan reverb:start
    restart: unless-stopped
    ports:
      - "8080:8080"
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
    update_or_add_env_var ".env" "APP_KEY" "base64:$LINE_APP_KEY" "APP_KEY"
    
    # 使用統一的函數安全地處理 JWT_SECRET
    update_or_add_env_var ".env" "JWT_SECRET" "$JWT_SECRET" "JWT_SECRET"
    
    # 添加或更新 APP_TIMEZONE 設定
    update_or_add_env_var ".env" "APP_TIMEZONE" "Asia/Taipei" "APP_TIMEZONE"
    
    # 添加或更新 JWT 相關設定
    update_or_add_env_var ".env" "JWT_TTL" "99999999999" "JWT_TTL"
    update_or_add_env_var ".env" "JWT_REFRESH_TTL" "99999999999" "JWT_REFRESH_TTL"
    update_or_add_env_var ".env" "JWT_ALGO" "HS256" "JWT_ALGO"
    
    # 添加或更新 APP_ENV 設定
    update_or_add_env_var ".env" "APP_ENV" "$APP_ENV" "APP_ENV"
    
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
    update_or_add_env_var ".env" "APP_URL" "https://line.$PROJECT_NAME_INPUT.$PROJECT_DOMAIN" "APP_URL"
    update_or_add_env_var ".env" "DB_CONNECTION" "mysql" "DB_CONNECTION"
    update_or_add_env_var ".env" "DB_HOST" "172.21.0.1" "DB_HOST"
    update_or_add_env_var ".env" "DB_PASSWORD" "$DB_LINEBOT_PASSWORD" "DB_PASSWORD"
    update_or_add_env_var ".env" "REDIS_PASSWORD" "$REDIS_PASSWORD_INPUT" "REDIS_PASSWORD"
    update_or_add_env_var ".env" "REDIS_HOST" "172.21.0.1" "REDIS_HOST"
    update_or_add_env_var ".env" "LINE_BOT_CHANNEL_BASIC_ID" "$LINE_BOT_CHANNEL_BASIC_ID" "LINE_BOT_CHANNEL_BASIC_ID"
    update_or_add_env_var ".env" "LINE_BOT_CHANNEL_ACCESS_TOKEN" "$LINE_BOT_CHANNEL_ACCESS_TOKEN" "LINE_BOT_CHANNEL_ACCESS_TOKEN"
    update_or_add_env_var ".env" "LINE_BOT_CHANNEL_ID" "$LINE_BOT_CHANNEL_ID" "LINE_BOT_CHANNEL_ID"
    update_or_add_env_var ".env" "LINE_BOT_CHANNEL_SECRET" "$LINE_BOT_CHANNEL_SECRET" "LINE_BOT_CHANNEL_SECRET"
    update_or_add_env_var ".env" "LINE_LOGIN_CHANNEL_ID" "$LINE_LOGIN_CHANNEL_ID" "LINE_LOGIN_CHANNEL_ID"
    update_or_add_env_var ".env" "LINE_LOGIN_CHANNEL_SECRET" "$LINE_LOGIN_CHANNEL_SECRET" "LINE_LOGIN_CHANNEL_SECRET"
    update_or_add_env_var ".env" "GOOGLE_CLOUD_STORAGE_PATH_PREFIX" "\"$GOOGLE_CLOUD_STORAGE_PATH_PREFIX\"" "GOOGLE_CLOUD_STORAGE_PATH_PREFIX"
    
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
# 給 nginx 使用者讀取權限
NGINX_USER=$(ps aux | grep '[n]ginx' | awk '{print $1}' | head -n 1)
if [ -z "$NGINX_USER" ]; then
    NGINX_USER="www-data"
fi
setfacl -Rd -m u:$NGINX_USER:rx /srv/aitago-web

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

# 偵測 Docker Compose 版本並設定命令
detect_docker_compose() {
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        echo "偵測到 Docker Compose Plugin 版本"
    elif docker-compose --version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        echo "偵測到 Docker Compose 獨立版本"
    else
        echo "錯誤: 無法偵測 Docker Compose"
        exit 1
    fi
}

show_help() {
    echo "Aitago 專案管理腳本"
    echo ""
    echo "用法: $0 [COMMAND] [PROJECT] [BRANCH]"
    echo ""
    echo "Commands:"
    echo "  start         啟動專案"
    echo "  stop          停止專案"
    echo "  restart       重啟專案"
    echo "  status        查看專案狀態"
    echo "  logs          查看專案日誌"
    echo "  build         重新建置專案"
    echo "  update        更新專案代碼並重新建置"
    echo "  switch-branch 切換到指定分支並重新建置"
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

# 偵測 Docker Compose 版本
detect_docker_compose

COMMAND=$1
PROJECT=$2
BRANCH=$3

if [ -z "$COMMAND" ] || [ -z "$PROJECT" ]; then
    show_help
    exit 1
fi

# 對於 switch-branch 命令，分支參數是必需的
if [ "$COMMAND" = "switch-branch" ] && [ -z "$BRANCH" ]; then
    echo "錯誤: switch-branch 命令需要指定分支名稱"
    echo "用法: $0 switch-branch [PROJECT] [BRANCH]"
    exit 1
fi

case $PROJECT in
    api)
        PROJECT_DIR="/srv/aitago-api"
        ;;
    crm|line)
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
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD up -d"
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD up -d"
        else
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD up -d"
        fi
        ;;
    stop)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD down"
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD down"
        else
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD down"
        fi
        ;;
    restart)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD restart"
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD restart"
        else
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD restart"
        fi
        ;;
    status)
        if [ "$PROJECT" = "all" ]; then
            echo "=== aitago-api 狀態 ==="
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD ps"
            echo ""
            echo "=== line-crm 狀態 ==="
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD ps"
        else
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD ps"
        fi
        ;;
    logs)
        if [ "$PROJECT" = "all" ]; then
            echo "請指定特定專案查看日誌"
            exit 1
        else
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD logs -f"
        fi
        ;;
    build)
        if [ "$PROJECT" = "all" ]; then
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD up -d --build"
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD up -d --build"
        else
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD up -d --build"
        fi
        echo "清理未使用的 Docker 映像..."
        docker image prune -f
        ;;
    update)
        if [ "$PROJECT" = "all" ]; then
            echo "=== 更新 aitago-api ==="
            execute_command "/srv/aitago-api/src" "sudo -u deploy git fetch origin"
            execute_command "/srv/aitago-api/src" "sudo -u deploy git pull origin \$(git branch --show-current)"
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD up -d --build"
            echo ""
            echo "=== 更新 line-crm ==="
            execute_command "/srv/line-crm/src" "sudo -u deploy git fetch origin"
            execute_command "/srv/line-crm/src" "sudo -u deploy git pull origin \$(git branch --show-current)"
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD up -d --build"
        else
            if [ "$PROJECT" = "api" ]; then
                execute_command "/srv/aitago-api/src" "sudo -u deploy git fetch origin"
                execute_command "/srv/aitago-api/src" "sudo -u deploy git pull origin \$(git branch --show-current)"
            elif [ "$PROJECT" = "crm" ]; then
                execute_command "/srv/line-crm/src" "sudo -u deploy git fetch origin"
                execute_command "/srv/line-crm/src" "sudo -u deploy git pull origin \$(git branch --show-current)"
            fi
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD up -d --build"
        fi
        echo "清理未使用的 Docker 映像..."
        docker image prune -f
        ;;
    switch-branch)
        if [ "$PROJECT" = "all" ]; then
            echo "=== 切換 aitago-api 到 $BRANCH 分支 ==="
            execute_command "/srv/aitago-api/src" "sudo -u deploy git fetch origin"
            execute_command "/srv/aitago-api/src" "sudo -u deploy git checkout $BRANCH"
            execute_command "/srv/aitago-api/src" "sudo -u deploy git pull origin $BRANCH"
            execute_command "/srv/aitago-api" "$DOCKER_COMPOSE_CMD up -d --build"
            echo ""
            echo "=== 切換 line-crm 到 $BRANCH 分支 ==="
            execute_command "/srv/line-crm/src" "sudo -u deploy git fetch origin"
            execute_command "/srv/line-crm/src" "sudo -u deploy git checkout $BRANCH"
            execute_command "/srv/line-crm/src" "sudo -u deploy git pull origin $BRANCH"
            execute_command "/srv/line-crm" "$DOCKER_COMPOSE_CMD up -d --build"
        else
            if [ "$PROJECT" = "api" ]; then
                echo "=== 切換 aitago-api 到 $BRANCH 分支 ==="
                execute_command "/srv/aitago-api/src" "sudo -u deploy git fetch origin"
                execute_command "/srv/aitago-api/src" "sudo -u deploy git checkout $BRANCH"
                execute_command "/srv/aitago-api/src" "sudo -u deploy git pull origin $BRANCH"
            elif [ "$PROJECT" = "crm" ]; then
                echo "=== 切換 line-crm 到 $BRANCH 分支 ==="
                execute_command "/srv/line-crm/src" "sudo -u deploy git fetch origin"
                execute_command "/srv/line-crm/src" "sudo -u deploy git checkout $BRANCH"
                execute_command "/srv/line-crm/src" "sudo -u deploy git pull origin $BRANCH"
            fi
            execute_command "$PROJECT_DIR" "$DOCKER_COMPOSE_CMD up -d --build"
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
