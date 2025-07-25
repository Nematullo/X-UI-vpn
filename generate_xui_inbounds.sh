#!/bin/bash

# Путь к файлу базы данных X-UI. Убедитесь, что этот путь верен.
DB_PATH="stabe-config/x-ui.db"

# Лимит трафика для каждого профиля в ГБ
TOTAL_GB_LIMIT=50
# Конвертируем ГБ в байты для базы данных
TOTAL_BYTES_LIMIT=$((TOTAL_GB_LIMIT * 1024 * 1024 * 1024))

# Начальный порт для создания инбаундов. Порты будут: 2003, 2004, ..., 2014
BASE_PORT=2003

# Массив с названиями месяцев на русском языке для имен профилей
MONTH_NAMES=(
    "Январь" "Февраль" "Март" "Апрель" "Май" "Июнь"
    "Июль" "Август" "Сентябрь" "Октябрь" "Ноябрь" "Декабрь"
)

# --- Предварительные проверки ---

# Проверяем, установлена ли утилита 'sqlite3'
if ! command -v sqlite3 &> /dev/null
then
    echo "Ошибка: Утилита 'sqlite3' не найдена. Пожалуйста, установите ее командой 'sudo apt install sqlite3'."
    exit 1
fi

# Проверяем, установлена ли утилита 'uuidgen'
if ! command -v uuidgen &> /dev/null
then
    echo "Ошибка: Утилита 'uuidgen' не найдена. Пожалуйста, установите ее командой 'sudo apt install uuid-runtime'."
    exit 1
fi

# Проверяем, существует ли файл базы данных по указанному пути
if [ ! -f "$DB_PATH" ]; then
    echo "Ошибка: Файл базы данных '$DB_PATH' не найден. Убедитесь, что путь верен и вы запускаете скрипт из нужной директории."
    exit 1
fi

echo "Начинаем модификацию базы данных X-UI: $DB_PATH"

# --- Шаг 1: Полностью очищаем таблицу 'inbounds' ---
echo "Очистка таблицы 'inbounds'..."
# Убедитесь, что контейнер X-UI остановлен перед запуском скрипта!
sqlite3 "$DB_PATH" "DELETE FROM inbounds;"
if [ $? -eq 0 ]; then
    echo "Таблица 'inbounds' успешно очищена."
else
    echo "Ошибка при очистке таблицы 'inbounds'. Убедитесь, что Docker-контейнер X-UI остановлен (docker stop x-ui-neo), затем попробуйте снова." >&2
    exit 1
fi

echo "Начинаем добавление 12 VLESS инбаундов..."

# --- Основной цикл: генерируем и добавляем 12 профилей ---

for i in $(seq 0 11); do
    # Определяем имя месяца и порт для текущего профиля
    MONTH_INDEX=$((i % 12)) # Индекс от 0 до 11 для массива MONTH_NAMES
    CURRENT_MONTH_NAME=${MONTH_NAMES[$MONTH_INDEX]} # Например, "Январь"
    CURRENT_PORT=$((BASE_PORT + i)) # Например, 2003, 2004, ...

    # Генерируем уникальные идентификаторы для клиента
    CLIENT_UUID=$(uuidgen)
    CLIENT_EMAIL="user_${CURRENT_MONTH_NAME}" # Email для клиента: user_Январь
    SUB_ID=$(uuidgen | tr -d '-' | head -c 16) # 16-символьный Sub ID без дефисов
    
    # Имя профиля, которое будет видно в X-UI панели
    PROFILE_NAME="${CURRENT_MONTH_NAME} Профиль" # Например, "Январь Профиль"

    # Вычисляем expiry_time (Unix-таймстамп конца месяца)
    # Используем текущий системный год
    CURRENT_YEAR=$(date +%Y)
    # Формируем дату первого числа следующего месяца, затем отнимаем 1 секунду.
    # Пример: для Января (i=0), вычисляем 2025-02-01 00:00:00, затем -1 секунда.
    # Для Декабря (i=11), вычисляем 2026-01-01 00:00:00, затем -1 секунда.
    EXPIRY_TIME=$(date -d "${CURRENT_YEAR}-$(printf "%02d" $((i+1)))-01 +1 month -1 second" +%s)

    # --- Формируем JSON-строки для различных настроек инбаунда с помощью 'here document' ---

    # 1. JSON для настроек протокола VLESS (поле 'settings' в БД)
    VLESS_SETTINGS_JSON=$(cat << EOF_VLESS_JSON
{
  "clients": [
    {
      "id": "${CLIENT_UUID}",
      "flow": "",
      "email": "${CLIENT_EMAIL}",
      "totalGB": ${TOTAL_BYTES_LIMIT},
      "expiryTime": ${EXPIRY_TIME},
      "enable": true,
      "tgId": "",
      "subId": "${SUB_ID}",
      "reset": 1
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
EOF_VLESS_JSON
)

    # 2. JSON для настроек потока (TLS, TCP) (поле 'stream_settings' в БД)
    STREAM_SETTINGS_JSON=$(cat << EOF_STREAM_JSON
{
  "network": "tcp",
  "security": "tls",
  "externalProxy": [],
  "tlsSettings": {
    "serverName": "t.me",
    "minVersion": "1.2",
    "maxVersion": "1.3",
    "cipherSuites": "",
    "rejectUnknownSni": false,
    "certificates": [
      {
        "certificateFile": "/certs/server.crt",
        "keyFile": "/certs/server.key",
        "ocspStapling": 3600
      }
    ],
    "alpn": [
      "h2",
      "http/1.1"
    ],
    "settings": {
      "allowInsecure": true,
      "fingerprint": "chrome"
    }
  },
  "tcpSettings": {
    "acceptProxyProtocol": false,
    "header": {
      "type": "none"
    }
  }
}
EOF_STREAM_JSON
)
    
    # 3. JSON для настроек сниффинга (поле 'sniffing' в БД)
    SNIFFING_JSON=$(cat << EOF_SNIFFING_JSON
{
  "enabled": true,
  "destOverride": [
    "http",
    "tls",
    "quic",
    "fakedns"
  ],
  "metadataOnly": false,
  "routeOnly": false
}
EOF_SNIFFING_JSON
)

    # Тег (метка) инбаунда, используется X-UI для внутренней идентификации
    INBOUND_TAG="inbound-${CURRENT_PORT}"

    # --- Подготовка SQL-запроса INSERT ---
    # Важно: Экранируем одиночные кавычки (') внутри JSON-строк для SQLite,
    # заменяя их на двойные одиночные кавычки ('')
    ESCAPED_VLESS_SETTINGS_JSON=$(echo "$VLESS_SETTINGS_JSON" | sed "s/'/''/g")
    ESCAPED_STREAM_SETTINGS_JSON=$(echo "$STREAM_SETTINGS_JSON" | sed "s/'/''/g")
    ESCAPED_SNIFFING_JSON=$(echo "$SNIFFING_JSON" | sed "s/'/''/g")

    # SQL INSERT запрос. Столбцы перечислены в порядке, соответствующем вашей БД.
    SQL_INSERT="
    INSERT INTO inbounds (
        user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing
    ) VALUES (
        1, 0, 0, $TOTAL_BYTES_LIMIT, '$PROFILE_NAME', 1, $EXPIRY_TIME, '0.0.0.0', $CURRENT_PORT, 'vless',
        '$ESCAPED_VLESS_SETTINGS_JSON',
        '$ESCAPED_STREAM_SETTINGS_JSON',
        '$INBOUND_TAG',
        '$ESCAPED_SNIFFING_JSON'
    );"

    # Выполняем SQL-запрос с помощью утилиты sqlite3
    sqlite3 "$DB_PATH" "$SQL_INSERT"
    
    # Проверяем код возврата команды sqlite3
    if [ $? -eq 0 ]; then
        echo "Успешно добавлен VLESS инбаунд: '$PROFILE_NAME' (Порт: $CURRENT_PORT, Пользователь: $CLIENT_EMAIL, Expiry: $(date -d @$EXPIRY_TIME))"
    else
        echo "Ошибка при добавлении VLESS инбаунда: '$PROFILE_NAME' (Порт: $CURRENT_PORT, Пользователь: $CLIENT_EMAIL)" >&2
        echo "Пожалуйста, проверьте схему таблицы 'inbounds' в вашей БД X-UI, выполнив:" >&2
        echo "sqlite3 $DB_PATH 'PRAGMA table_info(inbounds);'" >&2
    fi

done

echo "---"
echo "Процесс добавления инбаундов в базу данных завершен."
echo "ВАЖНО: Теперь вам нужно перезапустить Docker-контейнер X-UI, чтобы новые профили появились в панели:"
echo "docker restart x-ui-neo"
echo "---"