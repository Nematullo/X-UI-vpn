# Используем официальный образ alireza7/x-ui как базовый
FROM alireza7/x-ui:latest

# Устанавливаем jq, openssl (для генерации сертификатов) и curl (для получения внешнего IP)
# Если alireza7/x-ui основан на Alpine, используем apk. Если на Debian/Ubuntu, но apt-get не работает,
# то, возможно, образ очень минималистичен.
# Давайте попробуем установить через apt-get, если он все же есть и проблема была в чем-то другом.
# Если снова будет exit code 127, значит apt-get либо нет, либо он работает не так.
# В таком случае, придется использовать multi-stage build или найти другой x-ui образ.

# Пробуем обычный apt-get install (если базовая ОС - Debian/Ubuntu)
RUN apt-get update && apt-get install -y --no-install-recommends jq openssl curl \
    && rm -rf /var/lib/apt/lists/*

# Создаем директорию для сертификатов внутри контейнера
RUN mkdir -p /etc/x-ui/certs

# *ВАЖНО:* Мы БОЛЬШЕ НЕ копируем config.json здесь.
# Этим будет заниматься generate_and_configure_certs.sh, если его нет.

# Копируем скрипт генерации и настройки сертификатов
COPY generate_and_configure_certs.sh /usr/local/bin/generate_and_configure_certs.sh

# Делаем скрипт исполняемым
RUN chmod +x /usr/local/bin/generate_and_configure_certs.sh

# Права доступа для директории конфигов (важно для записи)
RUN chmod 755 /etc/x-ui/

# Устанавливаем ENTRYPOINT: сначала запускаем наш скрипт, затем оригинальный X-UI
ENTRYPOINT ["/bin/bash", "-c", "/usr/local/bin/generate_and_configure_certs.sh && /usr/local/x-ui/x-ui"]

# Декларируем порты, которые будут использоваться ВНУТРИ контейнера
# Внутренний порт веб-панели X-UI
EXPOSE 54321
# Внутренние порты для VPN-трафика
EXPOSE 2003-2025