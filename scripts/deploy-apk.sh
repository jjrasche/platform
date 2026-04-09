#!/bin/bash
# Deploy an APK to the app distribution server
# Usage: ./scripts/deploy-apk.sh <app-slug> <version> <path-to-apk>
# Example: ./scripts/deploy-apk.sh houseops 0.1.0 ../house-ops/apps/expo/android/app/build/outputs/apk/release/app-release.apk
set -euo pipefail

APP_SLUG="${1:?Usage: deploy-apk.sh <app-slug> <version> <apk-path>}"
VERSION="${2:?Usage: deploy-apk.sh <app-slug> <version> <apk-path>}"
APK_PATH="${3:?Usage: deploy-apk.sh <app-slug> <version> <apk-path>}"

SSH_KEY="~/.ssh/id_platform"
SERVER="deploy@${PLATFORM_IP:?Set PLATFORM_IP env var}"
DIST_DIR="/opt/app-dist/${APP_SLUG}"
DEST_FILE="${APP_SLUG}-${VERSION}.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    exit 1
fi

echo "Deploying ${DEST_FILE} to ${SERVER}:${DIST_DIR}/"
ssh -i "$SSH_KEY" "$SERVER" "sudo mkdir -p ${DIST_DIR} && sudo chown deploy:deploy ${DIST_DIR}"
scp -i "$SSH_KEY" "$APK_PATH" "${SERVER}:${DIST_DIR}/${DEST_FILE}"
echo "Done. Download at: https://apps.jimr.fyi/${APP_SLUG}/${DEST_FILE}"
