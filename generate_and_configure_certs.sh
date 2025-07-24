#!/bin/bash

# Пути для сертификатов внутри контейнера
CERT_DIR="/etc/x-ui/certs"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"
CONFIG_FILE="/etc/x-ui/config.json"

# Создаем директорию для сертификатов, если она не существует
mkdir -p "$CERT_DIR"

# Автоматически получаем внешний IP-адрес раннера.
# Используем ifconfig.me как надежный сервис.
# Убедитесь, что 'curl' доступен в Docker-образе (см Dockerfile ниже).
DOMAIN_OR_IP=$(curl -s ifconfig.me)

if [ -z "$DOMAIN_OR_IP" ]; then
    echo "ERROR: Could not get external IP address. Exiting."
    exit 1
fi

echo "Generating new self-signed certificate for IP: $DOMAIN_OR_IP"

# Генерируем новый самоподписанный сертификат и ключ
# Добавляем Subject Alternative Name (SAN) для IP-адреса,
# что важно для современных клиентов, которые предпочитают SAN полю CN.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=$DOMAIN_OR_IP" \
    -addext "subjectAltName = IP:$DOMAIN_OR_IP" # <-- Добавляем SAN для IP

echo "Generated certificate: $CERT_FILE"
echo "Generated key: $KEY_FILE"

# Обновляем config.json X-UI, чтобы использовать эти новые сертификаты
# Используем jq для безопасного редактирования JSON.
# Этот скрипт обновит inbounds, у которых enableTls: true,
# установит пути к новым сертификатам и обновит serverName на текущий IP.
if command -v jq &> /dev/null
then
    jq --arg cert_file "$CERT_FILE" \
       --arg key_file "$KEY_FILE" \
       --arg ip_addr "$DOMAIN_OR_IP" \
       '.inbounds[] |= if .enableTls == true then
         (.settings.reality.fingerprints = "" |
          .streamSettings.tlsSettings.certificates[0].certificateFile = $cert_file |
          .streamSettings.tlsSettings.certificates[0].keyFile = $key_file |
          .streamSettings.tlsSettings.serverName = $ip_addr)
       else . end' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    echo "Updated X-UI config.json with new certificate paths and serverName: $DOMAIN_OR_IP."
else
    echo "WARNING: jq is not installed. Cannot automatically update config.json."
    echo "Please ensure config.json points to: certFile: $CERT_FILE, keyFile: $KEY_FILE, and serverName: $DOMAIN_OR_IP"
fi

# Устанавливаем права доступа для сгенерированных файлов
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"