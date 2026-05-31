#!/bin/bash
# Script tải GLPI về host trước khi build Docker
# Dùng: sudo bash download-glpi.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env"

TGZ_FILE="${SCRIPT_DIR}/glpi-${GLPI_VERSION}.tgz"

if [ -f "${TGZ_FILE}" ]; then
    echo ">>> File đã tồn tại: ${TGZ_FILE}, bỏ qua tải."
    exit 0
fi

echo ">>> Đang tải GLPI ${GLPI_VERSION}..."
wget -c --progress=bar \
    "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" \
    -O "${TGZ_FILE}"

echo ">>> Tải xong: ${TGZ_FILE}"
echo ">>> Giờ chạy: sudo docker compose build"