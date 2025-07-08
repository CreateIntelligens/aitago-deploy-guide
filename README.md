# Aitago 自動化部署腳本

本目錄包含了 Aitago 專案的自動化部署腳本，可以快速完成從伺服器初始化到專案部署的全部流程。

## 腳本列表

### 1. `server_init.sh` - 伺服器初始化

- 設定系統時區
- 安裝必要套件 (git, redis-tools, certbot, mysql-client)
- 安裝 Docker 和 Docker Compose
- 建立 deploy 使用者

### 2. `infrastructure_deploy.sh` - 基礎設施部署

- 建立 Docker 網路
- 部署 MySQL 8.0
- 部署 Redis
- 自動建立資料庫和使用者
- 包含健康檢查

### 3. `project_deploy.sh` - 專案部署

- 部署 aitago-api (後端 API)
- 部署 line-crm (Line CRM 系統)
- 準備 aitago-web (前端網站)
- 建立專案管理腳本

### 4. `nginx_ssl_setup.sh` - Nginx 設定和 SSL 憑證

- 建立 Nginx 反向代理設定
- 申請 Let's Encrypt SSL 憑證
- 設定自動續期
- 包含 CORS 設定

### 5. `deploy_all.sh` - 完整部署

- 按順序執行所有部署步驟
- 互動式設定
- 錯誤處理

## 使用方式

### 快速部署 (推薦)

```bash
# 下載所有腳本後執行
sudo bash deploy_all.sh
```

### 分步驟部署

```bash
# 1. 伺服器初始化
sudo bash server_init.sh

# 2. 基礎設施部署
sudo bash infrastructure_deploy.sh

# 3. 專案部署
sudo bash project_deploy.sh

# 4. Nginx 設定和 SSL 憑證
sudo bash nginx_ssl_setup.sh
```

## 部署前準備

1. **伺服器要求**
   - Ubuntu 18.04+ 或 Debian 10+
   - 至少 2GB RAM
   - 至少 20GB 儲存空間
   - Root 或 sudo 權限

2. **網路要求**
   - 穩定的網路連接
   - 開放 80, 443 端口
   - 域名 DNS 已指向伺服器

3. **準備資訊**
   - 專案名稱
   - 主域名
   - Git 儲存庫 URL
   - 管理員郵箱 (用於 SSL 憑證)

## 部署後設定

### 1. 編輯專案設定檔

```bash
# 編輯 aitago-api 設定
sudo vim /srv/aitago-api/src/.env

# 編輯 line-crm 設定
sudo vim /srv/line-crm/src/.env
```

### 2. 啟動專案容器

```bash
# 啟動所有專案
/srv/manage_projects.sh start all

# 或分別啟動
/srv/manage_projects.sh start api
/srv/manage_projects.sh start crm
```

### 3. 上傳前端檔案

```bash
# 上傳打包好的前端檔案到
/srv/aitago-web/
```

## 管理命令

### 專案管理

```bash
# 查看所有專案狀態
/srv/manage_projects.sh status all

# 重新啟動專案
/srv/manage_projects.sh restart api

# 更新專案代碼並重新建置
/srv/manage_projects.sh update all

# 查看專案日誌
/srv/manage_projects.sh logs crm
```

### 基礎設施管理

```bash
# 查看基礎設施狀態
cd /srv/docker-compose && sudo docker compose ps

# 重新啟動基礎設施
cd /srv/docker-compose && sudo docker compose restart

# 查看基礎設施日誌
cd /srv/docker-compose && sudo docker compose logs
```

### Nginx 管理

```bash
# 測試 Nginx 設定
sudo nginx -t

# 重新載入 Nginx
sudo systemctl reload nginx

# 查看 Nginx 狀態
sudo systemctl status nginx
```

### SSL 憑證管理

```bash
# 查看憑證狀態
sudo certbot certificates

# 手動續期憑證
sudo certbot renew

# 測試憑證續期
sudo certbot renew --dry-run
```

## 目錄結構

部署完成後的目錄結構：

```txt
/srv/
├── docker-compose/          # 基礎設施 (MySQL, Redis)
│   ├── .env
│   ├── docker-compose.yaml
│   ├── mysql/
│   ├── mysql-init/
│   └── redis/
├── aitago-api/              # 後端 API
│   ├── src/
│   └── docker-compose.yaml
├── line-crm/                # Line CRM 系統
│   ├── src/
│   └── docker-compose.yaml
├── aitago-web/              # 前端網站 (靜態檔案)
└── manage_projects.sh       # 專案管理腳本
```

## 服務端口

- MySQL: 3306
- Redis: 6379
- aitago-api: 9002
- line-crm: 9001
- reverb-server: 8080
- Nginx: 80, 443

## 故障排除

### 常見問題

1. **Docker 權限問題**

   ```bash
   sudo usermod -aG docker $USER
   # 重新登入後生效
   ```

2. **端口被占用**

   ```bash
   sudo netstat -tulpn | grep :端口號
   sudo kill -9 PID
   ```

3. **SSL 憑證申請失敗**
   - 確認域名 DNS 設定正確
   - 確認防火牆開放 80, 443 端口
   - 檢查 Nginx 設定是否正確

4. **專案容器啟動失敗**
   - 檢查 .env 檔案設定
   - 檢查 Docker 映像是否建置成功
   - 查看容器日誌

### 查看日誌

```bash
# 專案日誌
/srv/manage_projects.sh logs api

# 基礎設施日誌
cd /srv/docker-compose && sudo docker compose logs

# Nginx 日誌
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# 系統日誌
sudo journalctl -u nginx -f
sudo journalctl -u docker -f
```

## 安全建議

1. **定期更新系統**

   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **設定防火牆**

   ```bash
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

3. **定期備份**
   - 定期備份 MySQL 資料庫
   - 定期備份專案程式碼
   - 定期備份 Nginx 設定

4. **監控系統資源**
   - 使用 `htop` 監控 CPU 和記憶體
   - 使用 `df -h` 監控磁碟空間
   - 設定日誌輪轉

## 支援

如果在使用過程中遇到問題，請檢查：

1. 腳本執行日誌
2. 系統日誌
3. 服務狀態
4. 網路連接

---

**注意**: 本腳本僅供參考，請根據實際環境調整設定。建議在測試環境中先行驗證後再應用到生產環境。
