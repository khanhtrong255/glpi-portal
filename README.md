# GLPI trên Docker — Hướng dẫn triển khai

## Cấu trúc dự án

```
/opt/docker-services/glpi/
├── .env                        # ⚠️  Thông tin nhạy cảm (KHÔNG commit Git)
├── .env.example                # Template để tham khảo
├── .gitignore
├── docker-compose.yml
├── Dockerfile
├── apache-glpi.conf            # Apache VirtualHost
├── docker-entrypoint.sh        # Startup script
├── glpi-cron                   # Cron job scheduler
├── mariadb/
│   └── conf.d/
│       └── glpi.cnf            # MariaDB tuning
└── logs/
    └── apache/                 # Apache logs (tự tạo)
```

---

## Yêu cầu

- Ubuntu Server 24.04 LTS
- Docker Engine + Docker Compose plugin
- NPM (Nginx Proxy Manager) đã chạy và có network `proxy_network`
- Domain đã trỏ A record về server

---

## Triển khai lần đầu

### 1. Clone/copy project về server

```bash
sudo mkdir -p /opt/docker-services/glpi
sudo cp -r . /opt/docker-services/glpi/
cd /opt/docker-services/glpi
```

### 2. Cấu hình biến môi trường

```bash
sudo cp .env.example .env
sudo nano .env
```

Chỉnh sửa bắt buộc:
- `MARIADB_ROOT_PASSWORD` — mật khẩu root DB
- `MARIADB_PASSWORD` — mật khẩu user GLPI
- `GLPI_DOMAIN` — domain thực tế của bạn
- `GLPI_VERSION` — kiểm tra phiên bản mới nhất tại https://github.com/glpi-project/glpi/releases

### 3. Phân quyền entrypoint

```bash
sudo chmod +x docker-entrypoint.sh
```

### 4. Build & khởi động stack

```bash
# Build image (lần đầu mất ~3-5 phút tải GLPI)
sudo docker compose build --no-cache

# Khởi động toàn bộ stack
sudo docker compose up -d

# Theo dõi logs khi khởi động
sudo docker compose logs -f
```

### 5. Kiểm tra các container đang chạy

```bash
sudo docker compose ps
```

Output mong đợi:
```
NAME            STATUS                   PORTS
glpi_mariadb    Up (healthy)
glpi_app        Up (healthy)
```

---

## Cấu hình NPM (Nginx Proxy Manager)

1. Đăng nhập NPM Admin UI
2. **Proxy Hosts → Add Proxy Host**
3. Điền thông tin:
   - **Domain Names:** `glpi.yourdomain.com`
   - **Scheme:** `http`
   - **Forward Hostname / IP:** `glpi_app`  ← tên container
   - **Forward Port:** `80`
   - Bật: **Block Common Exploits**, **Websockets Support**
4. Tab **SSL:** Request Let's Encrypt certificate, bật **Force SSL**
5. Tab **Advanced** — thêm custom config:

```nginx
client_max_body_size 20M;

proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

---

## Cài đặt GLPI lần đầu (Web Installer)

1. Truy cập `https://glpi.yourdomain.com`
2. Chọn ngôn ngữ → **OK**
3. Chấp nhận License → **Continue**
4. Chọn **Install** (không phải Update)
5. Điền thông tin database:
   - **SQL Server:** `mariadb` ← tên service trong compose
   - **Database user:** giá trị `MARIADB_USER` trong `.env`
   - **Password:** giá trị `MARIADB_PASSWORD` trong `.env`
   - **Database:** giá trị `MARIADB_DATABASE` trong `.env`
6. Hoàn tất wizard → đăng nhập với `glpi / glpi`

### ⚠️  Sau khi cài xong — BẮT BUỘC:

```bash
# Xóa file install.php (bảo mật)
sudo docker exec glpi_app rm -f /var/www/glpi/install/install.php
```

**Đổi mật khẩu mặc định ngay:**
- `glpi` / `glpi` → tài khoản admin
- `tech` / `tech` → tài khoản tech
- `normal` / `normal` → tài khoản normal
- `post-only` / `postonly` → tài khoản post-only

---

## Cấu hình URL trong GLPI

Vào **Setup → General → General setup:**
- **URL of the GLPI server:** `https://glpi.yourdomain.com`

---

## Quản lý thường ngày

### Xem logs

```bash
# Tất cả services
sudo docker compose logs -f

# Chỉ GLPI app
sudo docker compose logs -f glpi

# Chỉ MariaDB
sudo docker compose logs -f mariadb

# Apache logs (từ host)
sudo tail -f /opt/docker-services/glpi/logs/apache/glpi_error.log
```

### Restart services

```bash
sudo docker compose restart glpi
sudo docker compose restart mariadb
```

### Dừng & khởi động lại toàn bộ

```bash
sudo docker compose down
sudo docker compose up -d
```

### Update GLPI lên phiên bản mới

```bash
# 1. Backup trước
sudo docker exec glpi_mariadb mysqldump -u root -p${MARIADB_ROOT_PASSWORD} ${MARIADB_DATABASE} > backup_$(date +%Y%m%d).sql

# 2. Đổi GLPI_VERSION trong .env
sudo nano .env

# 3. Rebuild image
sudo docker compose build --no-cache glpi

# 4. Recreate container
sudo docker compose up -d glpi

# 5. Chạy migration (nếu cần) qua web hoặc CLI
sudo docker exec -u www-data glpi_app php /var/www/glpi/bin/console db:update
```

---

## Backup

### Backup database

```bash
#!/bin/bash
# Lưu vào /opt/backups/glpi/
BACKUP_DIR="/opt/backups/glpi"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "${BACKUP_DIR}"

sudo docker exec glpi_mariadb mysqldump \
  -u root -p"$(grep MARIADB_ROOT_PASSWORD /opt/docker-services/glpi/.env | cut -d= -f2)" \
  --single-transaction \
  --routines \
  --triggers \
  glpidb > "${BACKUP_DIR}/glpi_db_${DATE}.sql"

# Giữ 7 ngày gần nhất
find "${BACKUP_DIR}" -name "*.sql" -mtime +7 -delete

echo "Backup xong: ${BACKUP_DIR}/glpi_db_${DATE}.sql"
```

### Backup files & config

```bash
sudo docker run --rm \
  -v glpi_files:/source/files:ro \
  -v glpi_config:/source/config:ro \
  -v /opt/backups/glpi:/backup \
  alpine tar czf /backup/glpi_data_$(date +%Y%m%d).tar.gz -C /source .
```

---

## Troubleshooting

### Container không start được

```bash
sudo docker compose logs glpi
sudo docker compose logs mariadb
```

### Kiểm tra kết nối DB từ GLPI container

```bash
sudo docker exec -it glpi_app bash
apt-get install -y mariadb-client
mysql -h mariadb -u glpiuser -p glpidb
```

### Xem PHP errors

```bash
sudo docker exec glpi_app tail -f /var/log/apache2/glpi_error.log
```

### Reset về trạng thái sạch (⚠️ xóa toàn bộ dữ liệu)

```bash
sudo docker compose down -v
sudo docker compose up -d
```

---

## Thông tin stack

| Component | Version | Ghi chú |
|-----------|---------|---------|
| GLPI | 10.0.x | Xem `.env` |
| PHP | 8.2 | Khuyến nghị cho GLPI 10.x |
| MariaDB | 11.4 LTS | Long Term Support |
| Apache | 2.4 | Built-in trong PHP image |
