#!/bin/bash
set -e

# ============================================================
# GLPI Docker Entrypoint
# ============================================================

GLPI_DIR="/var/www/glpi"
DATA_DIR="/var/glpi-data"
CONFIG_DIR="${DATA_DIR}/config"
FILES_DIR="${DATA_DIR}/files"

echo ">>> [GLPI] Khởi động container..."

# --- 1. Đảm bảo thư mục dữ liệu tồn tại & đúng quyền ---
mkdir -p "${FILES_DIR}" "${CONFIG_DIR}"
chown -R www-data:www-data "${DATA_DIR}"

# --- 2. Symlink thư mục files & config ra ngoài webroot ---
# Giúp dữ liệu tồn tại khi container recreate
if [ ! -L "${GLPI_DIR}/files" ]; then
    rm -rf "${GLPI_DIR}/files"
    ln -s "${FILES_DIR}" "${GLPI_DIR}/files"
    echo ">>> [GLPI] Linked files/ -> ${FILES_DIR}"
fi

if [ ! -L "${GLPI_DIR}/config" ]; then
    rm -rf "${GLPI_DIR}/config"
    ln -s "${CONFIG_DIR}" "${GLPI_DIR}/config"
    echo ">>> [GLPI] Linked config/ -> ${CONFIG_DIR}"
fi

# --- 3. Quyền cho GLPI marketplace & plugins ---
mkdir -p "${GLPI_DIR}/marketplace" "${GLPI_DIR}/plugins"
chown -R www-data:www-data \
    "${GLPI_DIR}/files" \
    "${GLPI_DIR}/config" \
    "${GLPI_DIR}/marketplace" \
    "${GLPI_DIR}/plugins"

# --- 4. Khởi động cron daemon ---
echo ">>> [GLPI] Khởi động cron..."
service cron start

echo ">>> [GLPI] Sẵn sàng. Khởi động Apache..."

# --- 5. Chạy CMD (apache2-foreground) ---
exec "$@"