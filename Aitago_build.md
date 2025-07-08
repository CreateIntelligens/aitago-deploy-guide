# Aitago 站台部署指南

本文檔旨在引導您完成 Aitago 專案的初次部署流程。

## 1. 伺服器初始化

### 1.1. 系統設定

```bash
# 檢查並設定主機時區為 Asia/Taipei
sudo timedatectl set-timezone Asia/Taipei
sudo timedatectl
```

### 1.2. 安裝必要套件

```bash
# 更新套件列表
sudo apt-get update

# 安裝 git, redis-cli, certbot, mysql-client
sudo apt-get install -y git redis-tools certbot python3-certbot-nginx mysql-client
```

### 1.3. 安裝 Docker

請參考官方文檔或使用以下命令安裝 Docker。

- **官方文檔**: [Docker 安裝指南](https://docs.docker.com/engine/install/ubuntu/)

```bash
# 1. 設定 Docker 的 apt 儲存庫
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 新增 Docker 儲存庫到 APT sources
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

# 2. 安裝 Docker 相關套件
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. 驗證安裝是否成功
sudo docker run hello-world
```

### 1.4. 建立 `deploy` 使用者

```bash
# 建立 deploy 使用者
sudo adduser deploy

# 鎖定密碼，使其無法透過密碼登入
sudo passwd -l deploy

# 將 deploy 使用者加入 google-sudoers 群組
sudo usermod -aG google-sudoers deploy

# 檢查 deploy 使用者所在的群組
groups deploy

# 建立 .ssh 資料夾並設定權限
sudo mkdir -p /home/deploy/.ssh
sudo touch /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys

# 從其他主機複製 deploy 使用者的 SSH 設定
# 方法1: 使用 gcloud compute scp (適用於 GCP 主機)
gcloud compute scp source-instance-name:/home/deploy/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys --zone=asia-east1-b
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys

# 方法2: 使用傳統 scp (適用於一般主機)
# sudo scp -i /path/to/your/private_key user@source-host:/home/deploy/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys

# 方法3: 手動複製內容 (先在來源主機執行 cat /home/deploy/.ssh/authorized_keys)
# echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...' | sudo tee -a /home/deploy/.ssh/authorized_keys

# 從其他主機複製 deploy 使用者的 git ssh 私鑰
# 方法1: 使用 gcloud compute scp (適用於 GCP 主機)
gcloud compute scp source-instance-name:/home/deploy/.ssh/id_rsa /home/deploy/.ssh/id_rsa --zone=asia-east1-b

# 方法2: 使用傳統 scp (適用於一般主機)
# sudo scp -i /path/to/your/private_key user@source-host:/home/deploy/.ssh/id_rsa /home/deploy/.ssh/id_rsa

# 設定正確的權限
sudo chmod 600 /home/deploy/.ssh/id_rsa
sudo chown deploy:deploy /home/deploy/.ssh/id_rsa
```

## 2. 基礎設施部署 (Docker)

此階段將部署 MySQL 和 Redis 等基礎服務。

### 2.1. 建立資料夾結構

```bash
# 專案將部署於 /srv 資料夾下
cd /srv

# 建立 docker-compose 相關資料夾
sudo mkdir -p docker-compose/mysql
sudo mkdir -p docker-compose/mysql-init
sudo mkdir -p docker-compose/redis
```

### 2.2. 建立 Docker 網路

```bash
sudo docker network create --subnet=172.21.0.0/16 --gateway=172.21.0.1 nginx-php
```

### 2.3. 建立環境變數檔案

```bash
sudo touch /srv/docker-compose/.env
```

`.env` 檔案內容：

```env
DB_ROOT_PASSWORD=your_root_password
REDIS_PASSWORD=your_redis_password
```

### 2.4. 建立 MySQL 初始化腳本

```bash
sudo touch /srv/docker-compose/mysql-init/init.sql
```

`init.sql` 檔案內容：

```sql
-- 初始化 Aitago 資料庫
CREATE DATABASE IF NOT EXISTS aitago DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'aitago'@'%' IDENTIFIED BY 'Ai3ta2go1%@';
GRANT ALL PRIVILEGES ON aitago.* TO 'aitago'@'%';
FLUSH PRIVILEGES;

-- 初始化 Line CRM 資料庫
CREATE DATABASE IF NOT EXISTS linebot DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'linebot'@'%' IDENTIFIED BY 'linebot';
GRANT ALL PRIVILEGES ON linebot.* TO 'linebot'@'%';
FLUSH PRIVILEGES;
```

### 2.5. 建立 `docker-compose.yaml`

```bash
sudo touch /srv/docker-compose/docker-compose.yaml
```

`docker-compose.yaml` 檔案內容：

```yaml
version: '3.3'

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

  redis:
    env_file:
      - .env
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - ./redis:/data:rw
    command: redis-server --requirepass ${REDIS_PASSWORD}
    networks:
      - nginx-php

networks:
    nginx-php:
        external: true
```

### 2.6. 啟動基礎服務

```bash
cd /srv/docker-compose
sudo docker-compose up -d
```

## 3. 專案部署

此階段將部署 `aitago-api`、`line-crm` 和 `aitago-web` 三個專案。

### 3.1. 部署 `aitago-api` (後端)

```bash
# 1. 建立專案資料夾並設定權限
cd /srv
sudo mkdir aitago-api
sudo chown deploy:deploy aitago-api

# 2. 使用 deploy 使用者克隆專案
sudo -u deploy bash -c "cd /srv/aitago-api && git clone <repository-url> ./src"

# 3. 建立 .env 檔案
cd /srv/aitago-api/src
sudo cp .env.example .env
# 接著請編輯 .env 檔案，設定資料庫等連線資訊
sudo vim .env
```

#### `aitago-api` 的 `.env` 設定重點

```env
APP_KEY=base64:your_app_key_here
APP_TIMEZONE=Asia/Taipei
APP_URL=https://api.{project_name}.{domain} # 替換為實際的
LINE_CRM_URL=https://line.{project_name}.{domain} # 替換為實際的 Line CRM URL
CORS_ALLOWED_ORIGINS=https://{project_name}.{domain} # 替換為實際的域名

DB_CONNECTION=mysql
DB_HOST=172.21.0.1
DB_PORT=3306
DB_DATABASE=aitago
DB_USERNAME=aitago
DB_PASSWORD=your_aitago_db_password # 替換為實際的 Aitago 資料庫密碼

REDIS_HOST=172.21.0.1
REDIS_PASSWORD=your_redis_password

# Mail 設定
MAIL_MAILER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME="your_email@gmail.com"
MAIL_PASSWORD="your_email_password"
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=${MAIL_USERNAME}
MAIL_FROM_NAME="${APP_NAME}"

# JWT 設定 要與 `line-crm` 的 JWT 設定一致
JWT_SECRET=your_jwt_secret
JWT_TTL=99999999999
JWT_REFRESH_TTL=99999999999
JWT_ALGO=HS256

FRONT_END_URL=https://{project_name}.{domain} # 替換為實際的前端 URL
```

#### `aitago-api` 的 `docker-compose.yaml`

```bash
# 在 /srv/aitago-api/ 目錄下建立 docker-compose.yaml
sudo touch /srv/aitago-api/docker-compose.yaml
```

檔案內容：

```yaml
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
```

#### 啟動 `aitago-api`

```bash
cd /srv/aitago-api
sudo docker-compose up -d --build
sudo docker image prune -f
```

### 3.2. 部署 `line-crm` (Line CRM)

```bash
# 1. 建立專案資料夾並設定權限
cd /srv
sudo mkdir line-crm
sudo chown deploy:deploy line-crm

# 2. 使用 deploy 使用者克隆專案
sudo -u deploy bash -c "cd /srv/line-crm && git clone <repository-url> ./src"

# 3. 建立 .env 檔案
cd /srv/line-crm/src
sudo cp .env.example .env
# 接著請編輯 .env 檔案，設定資料庫等連線資訊
sudo vim .env
# 還需要將GCS key 檔案上傳至 /srv/line-crm/src/storage/app/ 目錄 並取名為 `gcp_storage_api_key.json`
```

#### `line-crm` 的 `.env` 設定重點

```env
APP_KEY=base64:your_app_key_here
APP_TIMEZONE=Asia/Taipei
APP_URL=https://line.{project_name}.{domain} # 替換為實際的域名

DB_CONNECTION=mysql
DB_HOST=172.21.0.1
DB_PORT=3306
DB_DATABASE=linebot
DB_USERNAME=linebot
DB_PASSWORD=your_linebot_db_password # 替換為實際的 Line CRM 資料庫密碼

REDIS_HOST=172.21.0.1
REDIS_PASSWORD=your_redis_password

LINE_BOT_CHANNEL_BASIC_ID=your_line_bot_channel_basic_id
LINE_BOT_CHANNEL_ACCESS_TOKEN=your_line_bot_channel_access_token
LINE_BOT_CHANNEL_ID=your_line_bot_channel_id
LINE_BOT_CHANNEL_SECRET=your_line_bot_channel_secret
LINE_LOGIN_CHANNEL_ID=your_line_login_channel_id
LINE_LOGIN_CHANNEL_SECRET=your_line_login_channel_secret

GOOGLE_CLOUD_STORAGE_PATH_PREFIX="project-name"

# JWT 設定 要與 `aitago-api` 的 JWT 設定一致
JWT_SECRET=your_jwt_secret
JWT_TTL=99999999999
JWT_REFRESH_TTL=99999999999
JWT_ALGO=HS256
```

#### `line-crm` 的 `docker-compose.yaml`

```bash
# 在 /srv/line-crm/ 目錄下建立 docker-compose.yaml
sudo touch /srv/line-crm/docker-compose.yaml
```

檔案內容：

```yaml
services:
  linebot:
    build:
        context: ./src
        dockerfile: Dockerfile
        args:
          - VITE_API_URL=https://feature-line-crm.aitago.tw # 替換為實際的 API URL
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
```

#### 啟動 `line-crm`

```bash
cd /srv/line-crm
sudo docker-compose up -d --build
sudo docker image prune -f
```

### 3.3. 部署 `aitago-web` (前端)

```bash
# 1. 建立專案資料夾並設定權限
cd /srv
sudo mkdir aitago-web
sudo chown -R deploy:deploy aitago-web
sudo find aitago-web -type d -exec chmod 2775 {} \;
sudo chmod -R 774 aitago-web
```

接下來，請於本地端拉取 `aitago-web` 的專案程式碼，設定好對應的 `.env` 檔案後，將打包好的靜態檔案上傳至 `/srv/aitago-web` 目錄。

## 4. Nginx 反向代理設定

### 4.1. 建立 Nginx 設定檔

```bash
# 切換到 /etc/nginx/conf.d 資料夾
cd /etc/nginx/conf.d

# 建立 nginx 配置檔案 (請將 {project_name}.{domain} 替換為實際名稱)
sudo touch line.{project_name}.{domain}.conf
sudo touch api.{project_name}.{domain}.conf
sudo touch {project_name}.{domain}.conf
```

### 4.2. 設定檔內容

#### `line.{project_name}.{domain}.conf`

```nginx
upstream linebot {
    server 127.0.0.1:9001;
    keepalive 16;
}

server {
    server_name line.{project_name}.{domain};

    index index.html index.htm index.php;

    access_log /var/log/nginx/line.{project_name}.{domain}.access.log;
    error_log /var/log/nginx/line.{project_name}.{domain}.error.log;
    root /var/www/html/public;

    client_max_body_size 200M;

    location / {
        proxy_pass http://linebot;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

    }


    # certbot 驗證路徑
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    location /reverb/ {
       proxy_pass http://127.0.0.1:8080;
       rewrite ^/reverb(/.*)$ $1 break;

       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
       proxy_read_timeout 600s;
       proxy_send_timeout 600s;

    }
}
```

#### `api.{project_name}.{domain}.conf`

```nginx
upstream api {
    server 127.0.0.1:9002;
    keepalive 16;
}

# HTTP server - 將所有 HTTP 重定向到 HTTPS
server {

    server_name api.{project_name}.{domain};

    index index.html index.htm index.php;

    access_log /var/log/nginx/api.{project_name}.{domain}.access.log;
    error_log /var/log/nginx/api.{project_name}.{domain}.error.log;
    root /var/www/html/public;

    client_max_body_size 200M;

    # 全局 CORS 設定 (適用於所有請求)
    set $cors_origin '*';
    set $cors_methods 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
    set $cors_headers 'DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization';

    location / {
        if ($request_method = OPTIONS) {
            add_header 'Access-Control-Allow-Origin' $cors_origin always;
            add_header 'Access-Control-Allow-Methods' $cors_methods always;
            add_header 'Access-Control-Allow-Headers' $cors_headers always;
            add_header 'Access-Control-Allow-Credentials' 'true' always;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain charset=UTF-8';
            return 204;
        }

        proxy_pass http://api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }


    # certbot 驗證路徑
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

}
```

#### `{project_name}.{domain}.conf`

```nginx
# HTTP server - 將所有 HTTP 重定向到 HTTPS
server {
    server_name {project_name}.{domain};
    
    root /srv/aitago-web;
    # certbot 驗證路徑
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    location / {
        index index.html index.htm index.php;
        try_files $uri $uri/ /index.html?$query_string;
    }
}
```

## 5. 啟用 SSL 並完成部署

### 5.1. 取得 SSL 憑證

```bash
# 建立 certbot 驗證用的資料夾
sudo mkdir -p /var/www/certbot

# 測試 Nginx 設定是否正確
sudo nginx -t

# 重啟 Nginx
sudo systemctl restart nginx

# 使用 certbot 取得 SSL 憑證 (請替換為您的域名)
sudo certbot --nginx -d line.{project_name}.{domain} -d api.{project_name}.{domain} -d {project_name}.{domain}
```

Certbot 會自動修改您的 Nginx 設定檔以啟用 HTTPS。

### 5.2. 最終重啟 Nginx

```bash
# 再次重啟 Nginx 以應用 SSL 憑證
sudo systemctl restart nginx
```

### 5.3. 資料庫同步 (可選)

若需要從舊主機同步 `linebot.templates` 資料表：

```bash
# 透過 ssh 從舊主機 mysqldump，並匯入到新主機
# (請替換 key 路徑、帳號、主機、密碼等資訊)
ssh -i /path/to/your/private_key user@old-host "mysqldump -u root -p'password' linebot templates" | mysql -u linebot -p'linebot' -h 127.0.0.1 linebot
```
> **注意**: 在命令列中直接使用密碼存在安全風險，建議使用其他更安全的方式。

部署完成！
