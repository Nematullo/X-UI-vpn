FROM alireza7/x-ui:latest

# (опционально) Создаём директорию для сертификатов
RUN mkdir -p /certs

EXPOSE 54321
EXPOSE 2003-2025