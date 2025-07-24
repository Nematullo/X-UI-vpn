# Используем официальный образ alireza7/x-ui как базовый
FROM alireza7/x-ui:latest

# Устанавливаем jq, openssl (для генерации сертификатов) и curl (для получения внешнего IP)
RUN apt-get update && apt-get install -y jq openssl curl \
    && rm -rf /var/lib/apt/lists/*

# Создаем директорию для сертификатов внутри контейнера
RUN mkdir -p /etc/x-ui/certs

# *ВАЖНО:* Мы БОЛЬШЕ НЕ копируем config.json здесь.
# Этим будет заниматься generate_and_configure_certs.sh

# Копируем скрипт генерации и настройки сертификатов
COPY generate_and_configure_certs.sh /usr/local/bin/generate_and_configure_certs.sh

# Делаем скрипт исполняемым
RUN chmod +x /usr/local/bin/generate_and_configure_certs.sh

# Права доступа для директории конфигов (важно для записи)
RUN chmod 755 /etc/x-ui/

# X-UI по умолчанию использует ENTRYPOINT ["/usr/local/x-ui/x-ui"].
# Мы должны запустить наш скрипт ПЕРЕД запуском X-UI.
# Используем bash для запуска скрипта, а затем передаем управление оригинальной точке входа X-UI.
ENTRYPOINT ["/bin/bash", "-c", "/usr/local/bin/generate_and_configure_certs.sh && /usr/local/x-ui/x-ui"]

# Декларируем порты, которые будут использоваться ВНУТРИ контейнера
# Внутренний порт веб-панели X-UI
EXPOSE 54321
# Внутренние порты для VPN-трафика
EXPOSE 2003-2025