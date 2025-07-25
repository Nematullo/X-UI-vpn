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
# !!! ВАЖНО: Убедитесь, что Docker-контейнер X-UI остановлен перед запуском скрипта!
# Выполните: docker stop x-ui-neo
sqlite3 "$DB_PATH" "DELETE FROM inbounds;"
if [ $? -eq 0 ]; then
    echo "Таблица 'inbounds' успешно очищена."
else
    echo "Ошибка при очистке таблицы 'inbounds'. Это может быть связано с тем, что Docker-контейнер X-UI все еще использует базу данных." >&2
    echo "Пожалуйста, остановите контейнер (команда: 'docker stop x-ui-neo') и затем запустите скрипт снова." >&2
    exit 1
fi

echo "Начинаем добавление 12 VLESS инбаундов..."

# --- Основной цикл: генерируем и добавляем 12 профилей ---

# Получаем текущий год системы ОДИН РАЗ
SYSTEM_CURRENT_YEAR=$(date +%Y)
SYSTEM_CURRENT_MONTH=$(date +%m)

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

    # --- Новый, более надежный способ вычисления expiry_time ---
    # Целевой месяц (1-12) и год для истечения срока
    TARGET_MONTH=$((MONTH_INDEX + 1)) # 1 для января, 12 для декабря

    # Если мы переходим в следующий календарный год (например, добавляем профиль для января следующего года)
    # В нашем случае, поскольку всего 12 профилей (Январь-Декабрь), все они будут в текущем году.
    TARGET_YEAR=$SYSTEM_CURRENT_YEAR

    # Вычисляем последний день целевого месяца в целевом году
    # Это делается путем получения первого дня *следующего* месяца, а затем вычитания 1 дня
    # Например, для января: 2025-02-01 - 1 день = 2025-01-31
    # Для декабря: 2026-01-01 - 1 день = 2025-12-31
    LAST_DAY_OF_TARGET_MONTH=$(date -d "${TARGET_YEAR}-$(printf "%02d" $((TARGET_MONTH + 1)))-01 -1 day" +%d 2>/dev/null)
    
    # Если последний день месяца не удалось получить (например, ошибка date)
    if [ -z "$LAST_DAY_OF_TARGET_MONTH" ]; then
        echo "Предупреждение: Не удалось получить последний день месяца для ${TARGET_YEAR}-$(printf "%02d" $TARGET_MONTH). Установка expiryTime в 0 (без срока действия)." >&2
        EXPIRY_TIME=0 # Устанавливаем в 0, если не удалось вычислить
    else
        # Формируем полную строку даты и времени для конца месяца (23:59:59)
        EXPIRY_DATETIME_STR="${TARGET_YEAR}-$(printf "%02d" $TARGET_MONTH)-${LAST_DAY_OF_TARGET_MONTH} 23:59:59"
        # Преобразуем в Unix-таймстамп
        EXPIRY_TIME=$(date -d "$EXPIRY_DATETIME_STR" +%s 2>/dev/null)
    fi

    # Дополнительная проверка, если EXPIRY_TIME все равно 0 (ошибка date)
    if [ "$EXPIRY_TIME" -eq 0 ]; then
        echo "Предупреждение: date вернул 0 для '$EXPIRY_DATETIME_STR'. Установка expiryTime в 0 (без срока действия)." >&2
        EXPIRY_TIME=0 # Гарантируем, что 0, если какая-то проблема с date
    fi

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
        # Дополнительная проверка и вывод для expiry_time
        if [ "$EXPIRY_TIME" -eq 0 ]; then
            echo "Успешно добавлен VLESS инбаунд: '$PROFILE_NAME' (Порт: $CURRENT_PORT, Пользователь: $CLIENT_EMAIL, Expiry: НЕТ СРОКА ДЕЙСТВИЯ (ошибка расчета))"
        else
            echo "Успешно добавлен VLESS инбаунд: '$PROFILE_NAME' (Порт: $CURRENT_PORT, Пользователь: $CLIENT_EMAIL, Expiry: $(date -d @$EXPIRY_TIME))"
        fi
    else
        echo "Ошибка при добавлении VLESS инбаунда: '$PROFILE_NAME' (Порт: $CURRENT_PORT, Пользователь: $CLIENT_EMAIL)" >&2
        echo "Пожалуйста, проверьте схему таблицы 'inbounds' в вашей БД X-UI, выполнив: sqlite3 $DB_PATH 'PRAGMA table_info(inbounds);'" >&2
    fi

done

echo "---"
echo "Процесс добавления инбаундов в базу данных завершен."
echo "ВАЖНО: Теперь вам нужно перезапустить Docker-контейнер X-UI, чтобы новые профили появились в панели:"
echo "docker restart x-ui-neo"
echo "---"