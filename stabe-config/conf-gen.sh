#!/bin/bash

# --- Конфигурируемые переменные ---
# Путь к файлу базы данных X-UI внутри контейнера.
# Предполагается, что x-ui.db будет смонтирован или скопирован в эту директорию /app.
XUI_DB_PATH="/app/x-ui.db"

# Email пользователя, чей UUID нужно обновить.
# Это значение будет передаваться как переменная окружения при запуске контейнера.
# Если переменная окружения не задана, используется значение по умолчанию.
TARGET_EMAIL="${TARGET_EMAIL:-user_to_update@example.com}" 

# --- Секретные переменные из GitHub Actions ---
# Значение NEW_SUB_JSON_URI берётся из GitHub Secrets через ENV (пример: ${{ secrets.URI }} в workflow)
NEW_SUB_JSON_URI="${NEW_SUB_JSON_URI:-}"

# --- Функции ---

# Функция для генерации нового UUID
generate_new_uuid() {
    # Команда uuidgen должна быть доступна в образе
    uuidgen
}

# --- Основная логика скрипта ---
echo "Начинаю обновление UUID в базе данных X-UI: $XUI_DB_PATH"
echo "Целевой email: $TARGET_EMAIL"

# Проверяем наличие файла базы данных
if [ ! -f "$XUI_DB_PATH" ]; then
    echo "Ошибка: Файл базы данных X-UI не найден по пути $XUI_DB_PATH"
    echo "Убедитесь, что x-ui.db смонтирован или скопирован в /app/x-ui.db."
    exit 1
fi

# Генерируем новый UUID
NEW_UUID=$(generate_new_uuid)
echo "Сгенерирован новый UUID: $NEW_UUID"

# Делаем резервную копию текущей базы данных.
# Эта резервная копия будет создана внутри смонтированного тома, т.е. на хосте.
cp "$XUI_DB_PATH" "$XUI_DB_PATH.bak_$(date +%Y%m%d%H%M%S)"
echo "Создана резервная копия базы данных: $XUI_DB_PATH.bak_$(date +%Y%m%d%H%M%S)"

# 1. Извлекаем текущую JSON-строку 'settings' для целевого пользователя
# Ищем запись, где в поле 'settings' есть JSON-объект с 'email', соответствующим TARGET_EMAIL.
CURRENT_SETTINGS_JSON=$(sqlite3 "$XUI_DB_PATH" "SELECT settings FROM inbounds WHERE settings LIKE '%\"email\":\"$TARGET_EMAIL\"%' LIMIT 1;")

if [ -z "$CURRENT_SETTINGS_JSON" ]; then
    echo "Ошибка: Пользователь с email '$TARGET_EMAIL' не найден в базе данных."
    exit 1
fi

echo "Найдена текущая конфигурация settings для пользователя $TARGET_EMAIL:"
echo "$CURRENT_SETTINGS_JSON" | jq .

# 2. Модифицируем JSON-строку с помощью 'jq', заменяя UUID
# Предполагается, что UUID находится по пути .clients[0].id.
# Если у вас другая структура (например, несколько клиентов в одном inbound),
# вам может потребоваться изменить путь к UUID.
UPDATED_SETTINGS_JSON=$(echo "$CURRENT_SETTINGS_JSON" | jq ".clients[0].id = \"$NEW_UUID\"")

if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось обновить JSON-строку с помощью 'jq'. Возможно, структура JSON отличается или пользователь не имеет 'clients[0].id'."
    exit 1
fi

echo "Новая конфигурация settings:"
echo "$UPDATED_SETTINGS_JSON" | jq .

# 3. Обновляем запись в базе данных SQLite
sqlite3 "$XUI_DB_PATH" "UPDATE inbounds SET settings = '$UPDATED_SETTINGS_JSON' WHERE settings LIKE '%\"email\":\"$TARGET_EMAIL\"%';"

if [ $? -eq 0 ]; then
    echo "UUID для пользователя '$TARGET_EMAIL' успешно обновлен в базе данных."
else
    echo "Ошибка при записи обновленных настроек в базу данных SQLite."
    exit 1
fi

echo "Скрипт завершен. Файл $XUI_DB_PATH теперь содержит обновленный UUID."

# --- Обновление ключа subJsonURI в settings ---

if [ -z "$NEW_SUB_JSON_URI" ]; then
    echo "Переменная NEW_SUB_JSON_URI не задана. Пропускаю обновление subJsonURI."
else
    # Извлекаем актуальный settings JSON (на случай, если он был обновлён выше)
    CURRENT_SETTINGS_JSON=$(sqlite3 "$XUI_DB_PATH" "SELECT settings FROM inbounds WHERE settings LIKE '%\"email\":\"$TARGET_EMAIL\"%' LIMIT 1;")
    if [ -z "$CURRENT_SETTINGS_JSON" ]; then
        echo "Ошибка: Не найден settings для пользователя $TARGET_EMAIL при попытке обновить subJsonURI."
        exit 1
    fi

    # Обновляем subJsonURI
    UPDATED_SETTINGS_JSON=$(echo "$CURRENT_SETTINGS_JSON" | jq ".subJsonURI = \"$NEW_SUB_JSON_URI\"")

    if [ $? -ne 0 ]; then
        echo "Ошибка: Не удалось обновить subJsonURI с помощью jq."
        exit 1
    fi

    # Записываем обратно в базу
    sqlite3 "$XUI_DB_PATH" "UPDATE inbounds SET settings = '$UPDATED_SETTINGS_JSON' WHERE settings LIKE '%\"email\":\"$TARGET_EMAIL\"%';"

    if [ $? -eq 0 ]; then
        echo "subJsonURI для пользователя '$TARGET_EMAIL' успешно обновлён в базе данных."
    else
        echo "Ошибка при записи обновлённого subJsonURI в базу данных SQLite."
        exit 1
    fi
fi

# --- Очистка таблицы users и добавление пользователя из секретов ---
AUTH="${AUTH:-}"
PASS="${PASS:-}"

if [ -n "$AUTH" ] && [ -n "$PASS" ]; then
    echo "Очищаю таблицу users и добавляю нового пользователя..."
    sqlite3 "$XUI_DB_PATH" "DELETE FROM users;"
    sqlite3 "$XUI_DB_PATH" "INSERT INTO users (auth, pass) VALUES ('$AUTH', '$PASS');"
    echo "Таблица пользователей очищена и добавлен новый пользователь."
else
    echo "AUTH или PASS не заданы — таблица users не изменяется."
fi