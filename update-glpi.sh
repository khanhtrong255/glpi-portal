#!/bin/bash
# ============================================================
# update-glpi.sh
# Tự động lấy GLPI version mới nhất từ GitHub và rebuild
# Dùng: sudo bash update-glpi.sh [--dry-run]
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
DRY_RUN=false
[[ "${1}" == "--dry-run" ]] && DRY_RUN=true

# --- Màu sắc output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> Kiểm tra phiên bản GLPI mới nhất...${NC}"

# --- Lấy latest version từ GitHub API ---
LATEST=$(curl -sf "https://api.github.com/repos/glpi-project/glpi/releases/latest" \
  | grep '"tag_name"' \
  | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [[ -z "${LATEST}" ]]; then
  echo -e "${RED}>>> Lỗi: Không lấy được version từ GitHub API.${NC}"
  exit 1
fi

# --- Đọc version hiện tại trong .env ---
CURRENT=$(grep "^GLPI_VERSION=" "${ENV_FILE}" | cut -d= -f2)

echo "    Hiện tại : ${CURRENT}"
echo "    Mới nhất : ${LATEST}"

if [[ "${CURRENT}" == "${LATEST}" ]]; then
  echo -e "${GREEN}>>> Đang dùng bản mới nhất rồi, không cần update.${NC}"
  exit 0
fi

echo -e "${YELLOW}>>> Có phiên bản mới: ${CURRENT} → ${LATEST}${NC}"

if [[ "${DRY_RUN}" == true ]]; then
  echo "    [dry-run] Không thực hiện thay đổi."
  exit 0
fi

# --- Backup .env ---
cp "${ENV_FILE}" "${ENV_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
echo "    .env đã backup xong."

# --- Backup database ---
echo -e "${GREEN}>>> Backup database trước khi update...${NC}"
source "${ENV_FILE}"
BACKUP_FILE="/opt/backups/glpi/pre_update_${CURRENT}_$(date +%Y%m%d_%H%M%S).sql"
mkdir -p /opt/backups/glpi
sudo docker exec glpi_mariadb mysqldump \
  -u root -p"${MARIADB_ROOT_PASSWORD}" \
  --single-transaction --routines --triggers \
  "${MARIADB_DATABASE}" > "${BACKUP_FILE}"
echo "    Backup DB: ${BACKUP_FILE}"

# --- Cập nhật .env ---
sed -i "s/^GLPI_VERSION=.*/GLPI_VERSION=${LATEST}/" "${ENV_FILE}"
echo "    GLPI_VERSION đã cập nhật → ${LATEST}"

# --- Rebuild & restart ---
echo -e "${GREEN}>>> Rebuild image GLPI...${NC}"
cd "${SCRIPT_DIR}"
sudo docker compose build --no-cache glpi

echo -e "${GREEN}>>> Khởi động lại container GLPI...${NC}"
sudo docker compose up -d glpi

# --- Chờ container healthy ---
echo -e "${GREEN}>>> Chờ GLPI khởi động...${NC}"
for i in {1..30}; do
  STATUS=$(sudo docker inspect --format='{{.State.Health.Status}}' glpi_app 2>/dev/null || echo "unknown")
  if [[ "${STATUS}" == "healthy" ]]; then
    echo -e "${GREEN}>>> GLPI đã sẵn sàng!${NC}"
    break
  fi
  echo "    Đang chờ... (${i}/30) status: ${STATUS}"
  sleep 5
done

# --- Chạy DB migration nếu cần ---
echo -e "${GREEN}>>> Kiểm tra DB migration...${NC}"
sudo docker exec -u www-data glpi_app \
  php /var/www/glpi/bin/console db:update --no-interaction || true

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  GLPI đã update lên ${LATEST} thành công!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Xóa file install.php nếu đây là lần đầu:"
echo "  sudo docker exec glpi_app rm -f /var/www/glpi/install/install.php"