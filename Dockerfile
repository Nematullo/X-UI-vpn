# Используем образ MHSanaei/x-ui с Docker Hub
FROM mhsanaei/x-ui:latest

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