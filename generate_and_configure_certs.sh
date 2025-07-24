#!/bin/bash

# Пути для сертификатов и конфига внутри контейнера
CERT_DIR="/etc/x-ui/certs"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"
FINAL_CONFIG_FILE="/etc/x-ui/config.json"
DEFAULT_XUI_CONFIG="/usr/local/x-ui/config.json" # Путь к дефолтному конфигу X-UI в базовом образе

# Создаем директорию для сертификатов, если она не существует
mkdir -p "$CERT_DIR"

# Проверяем, существует ли пользовательский config.json
if [ ! -f "$FINAL_CONFIG_FILE" ]; then
    echo "Custom config.json not found at $FINAL_CONFIG_FILE. Copying default X-UI config."
    # Копируем дефолтный конфиг X-UI, если пользовательский не предоставлен
    cp "$DEFAULT_XUI_CONFIG" "$FINAL_CONFIG_FILE"
    # Важно: Дефолтный конфиг может не иметь enableTls: true или нужных портов.
    # Вам, возможно, придется вручную настроить его через веб-интерфейс первый раз,
    # а потом сохранить его и использовать как свой базовый.
    # Или добавить сложную логику jq здесь для инициализации.
fi

# Автоматически получаем внешний IP-адрес раннера.
DOMAIN_OR_IP=$(curl -s ifconfig.me)

if [ -z "$DOMAIN_OR_IP" ]; then
    echo "ERROR: Could not get external IP address. Exiting."
    exit 1
fi

echo "Generating new self-signed certificate for IP: $DOMAIN_OR_IP"

# Генерируем новый самоподписанный сертификат и ключ
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=$DOMAIN_OR_IP" \
    -addext "subjectAltName = IP:$DOMAIN_OR_IP"

echo "Generated certificate: $CERT_FILE"
echo "Generated key: $KEY_FILE"

# Устанавливаем права доступа для сгенерированных файлов
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"

# Обновляем config.json X-UI, чтобы использовать эти новые сертификаты
# Используем jq для безопасного редактирования JSON.
# Этот скрипт обновит inbounds, у которых enableTls: true,
# установит пути к новым сертификатам и обновит serverName на текущий IP.
# *ВНИМАНИЕ*: Если вы используете дефолтный конфиг X-UI,
# у него может не быть inbounds с enableTls: true.
# В таком случае, этот jq-скрипт ничего не изменит,
# и вам придется вручную включить TLS для ваших inbounds через веб-панель
# после первого запуска!
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
       else . end' "$FINAL_CONFIG_FILE" > "$FINAL_CONFIG_FILE.tmp" && mv "$FINAL_CONFIG_FILE.tmp" "$FINAL_CONFIG_FILE"
    echo "Updated X-UI config.json with new certificate paths and serverName: $DOMAIN_OR_IP."
else
    echo "WARNING: jq is not installed. Cannot automatically update config.json."
    echo "Please ensure config.json points to: certFile: $CERT_FILE, keyFile: $KEY_FILE, and serverName: $DOMAIN_OR_IP"
fi

# Устанавливаем права доступа для файла конфигурации
chmod 644 "$FINAL_CONFIG_FILE"