# Используем официальный образ alireza7/x-ui как базовый
FROM alireza7/x-ui:latest

# Устанавливаем jq, openssl (для генерации сертификатов) и curl (для получения внешнего IP)
RUN apt-get update && apt-get install -y jq openssl curl \
    && rm -rf /var/lib/apt/lists/*

# Создаем директорию для сертификатов внутри контейнера
RUN mkdir -p /etc/x-ui/certs

# Копируем ваш готовый файл конфигурации X-UI (config.json)
# config.json должен быть преднастроен с enableTls: true для нужных inbounds,
# а пути к сертификатам и serverName будут перезаписаны скриптом.
COPY ./config.json /etc/x-ui/config.json

# Копируем скрипт генерации и настройки сертификатов
COPY generate_and_configure_certs.sh /usr/local/bin/generate_and_configure_certs.sh

# Делаем скрипт исполняемым
RUN chmod +x /usr/local/bin/generate_and_configure_certs.sh

# Устанавливаем права доступа для файла конфигурации
RUN chmod 644 /etc/x-ui/config.json

# X-UI по умолчанию использует ENTRYPOINT ["/usr/local/x-ui/x-ui"].
# Мы должны запустить наш скрипт ПЕРЕД запуском X-UI.
# Используем bash для запуска скрипта, а затем передаем управление оригинальной точке входа X-UI.
ENTRYPOINT ["/bin/bash", "-c", "/usr/local/bin/generate_and_configure_certs.sh && /usr/local/x-ui/x-ui"]

# Декларируем порты, которые будут использоваться ВНУТРИ контейнера
EXPOSE 54321    # Внутренний порт веб-панели X-UI
EXPOSE 2003-2025 # Внутренние порты для VPN-трафика