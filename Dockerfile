FROM alireza7/x-ui:latest

# (опционально) Создаём директорию для сертификатов
RUN mkdir -p /certs

COPY stabe-config/x-ui.db /etc/x-ui/x-ui.db


EXPOSE 54321
EXPOSE 2003-2025