# Используем легковесный базовый образ Ubuntu
FROM ubuntu:22.04

# Устанавливаем необходимые пакеты:
# apt-utils, dialog - для стабильной работы apt-get
# jq, openssl, curl - для нашего скрипта
# git, nodejs, npm - для установки X-UI (панель X-UI написана на Node.js)
RUN apt-get update && apt-get install -y \
    apt-utils \
    dialog \
    jq \
    openssl \
    curl \
    git \
    nodejs \
    npm \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Создаем директорию для X-UI и сертификатов
RUN mkdir -p /etc/x-ui/certs /usr/local/x-ui

# Клонируем репозиторий X-UI и устанавливаем зависимости
WORKDIR /usr/local/x-ui
RUN git clone https://github.com/alireza7/x-ui.git . \
    && npm install --omit=dev

# Копируем наш скрипт генерации и настройки сертификатов
COPY generate_and_configure_certs.sh /usr/local/bin/generate_and_configure_certs.sh

# Делаем скрипт исполняемым
RUN chmod +x /usr/local/bin/generate_and_configure_certs.sh

# Права доступа для директории конфигов (важно для записи)
RUN chmod 755 /etc/x-ui/

# Устанавливаем ENTRYPOINT: сначала запускаем наш скрипт, затем X-UI
ENTRYPOINT ["/bin/bash", "-c", "/usr/local/bin/generate_and_configure_certs.sh && node /usr/local/x-ui/bin/x-ui"]

# Декларируем порты, которые будут использоваться ВНУТРИ контейнера
# Внутренний порт веб-панели X-UI
EXPOSE 54321
# Внутренние порты для VPN-трафика
EXPOSE 2003-2025