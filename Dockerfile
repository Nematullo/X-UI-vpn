# Используем образ MHSanaei/x-ui с GitHub Container Registry как базовый
# Он, вероятно, содержит необходимые утилиты или более подходящую среду.
FROM ghcr.io/mhsanaei/x-ui:latest

# Проверяем, установлены ли jq, openssl, curl. Если нет, пытаемся установить.
# Использование apt-get update && apt-get install -y --no-install-recommends ...
# может не потребоваться, если образ уже их содержит.
# Если снова будет ошибка 127, значит, они уже есть или образ не на основе Debian/Ubuntu.
# В этом случае, мы можем просто убрать эту RUN-строку.
# Для первого раза оставим, чтобы проверить.
RUN apt-get update && apt-get install -y --no-install-recommends jq openssl curl \
    && rm -rf /var/lib/apt/lists/*

# Создаем директорию для сертификатов внутри контейнера
RUN mkdir -p /etc/x-ui/certs

# Копируем скрипт генерации и настройки сертификатов
COPY generate_and_configure_certs.sh /usr/local/bin/generate_and_configure_certs.sh

# Делаем скрипт исполняемым
RUN chmod +x /usr/local/bin/generate_and_configure_certs.sh

# Права доступа для директории конфигов (важно для записи)
RUN chmod 755 /etc/x-ui/

# Устанавливаем ENTRYPOINT: сначала запускаем наш скрипт, затем оригинальный X-UI
# Предполагаем, что исполняемый файл X-UI находится по стандартному пути.
ENTRYPOINT ["/bin/bash", "-c", "/usr/local/bin/generate_and_configure_certs.sh && /usr/local/x-ui/x-ui"]

# Декларируем порты, которые будут использоваться ВНУТРИ контейнера
# Внутренний порт веб-панели X-UI
EXPOSE 54321
# Внутренние порты для VPN-трафика
EXPOSE 2003-2025