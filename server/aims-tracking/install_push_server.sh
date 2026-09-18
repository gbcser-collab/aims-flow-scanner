#!/usr/bin/env bash
set -euo pipefail

KEY_SRC="${1:-}"
TRACKING_DIR="${2:-$(pwd)}"
KEY_DIR="/etc/aims-flow"
KEY_DST="$KEY_DIR/firebase-service-account.json"
CRON_FILE="/etc/cron.d/aims-flow-push"

if [ -z "$KEY_SRC" ] || [ ! -f "$KEY_SRC" ]; then
  echo "Usage: sudo $0 /path/to/firebase-service-account.json /absolute/path/to/aims-tracking"
  exit 2
fi

if [ ! -f "$TRACKING_DIR/push_worker.php" ] || [ ! -f "$TRACKING_DIR/push_service.php" ]; then
  echo "Tracking backend not found in: $TRACKING_DIR"
  exit 3
fi

PHP_BIN="$(command -v php || true)"
if [ -z "$PHP_BIN" ]; then
  echo "PHP CLI is required."
  exit 4
fi

for ext in openssl curl mbstring pdo_sqlite; do
  if ! "$PHP_BIN" -m | tr '[:upper:]' '[:lower:]' | grep -qx "$ext"; then
    echo "Missing PHP extension: $ext"
    exit 5
  fi
done

PROJECT_ID="$("$PHP_BIN" -r '
  $j=json_decode(file_get_contents($argv[1]), true);
  if (!is_array($j) || ($j["type"] ?? "") !== "service_account") exit(10);
  foreach (["project_id","client_email","private_key"] as $k) {
    if (empty($j[$k])) exit(11);
  }
  echo $j["project_id"];
' "$KEY_SRC")"

if [ "$PROJECT_ID" != "aims-flow" ]; then
  echo "Unexpected Firebase project_id: $PROJECT_ID"
  exit 6
fi

sudo install -d -m 700 "$KEY_DIR"
sudo install -m 600 "$KEY_SRC" "$KEY_DST"
sudo chown root:root "$KEY_DST"

TMP_CRON="$(mktemp)"
cat > "$TMP_CRON" <<EOF
* * * * * root $PHP_BIN $TRACKING_DIR/push_worker.php 25 >/dev/null 2>&1
EOF
sudo install -m 644 "$TMP_CRON" "$CRON_FILE"
rm -f "$TMP_CRON"

echo "Firebase service account installed: $KEY_DST"
echo "Push worker cron installed: $CRON_FILE"
echo "Running one safe queue check..."
sudo "$PHP_BIN" "$TRACKING_DIR/push_worker.php" 25
echo "AIMS Flow FCM server setup complete."
