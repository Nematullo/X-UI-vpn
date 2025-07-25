#!/bin/sh
# Имя файла: generate_cert.sh

# Указываем имена файлов для ключа и сертификата
KEY_FILE="server.key"
CERT_FILE="server.crt"

# Параметры для самоподписанного сертификата.
# Замените 'localhost' на ваше доменное имя или IP-адрес, если это необходимо.
# C (Country), ST (State/Province), L (Locality), O (Organization), OU (Organizational Unit), CN (Common Name)
SUBJECT="/C=NL/ST=NorthHolland/L=Amsterdam/O=MyTestOrg/OU=CertGenUnit/CN=localhost"

# Срок действия сертификата в днях
DAYS_VALID=365

echo "---"
echo "Запуск генерации нового самоподписанного сертификата..."

# Генерируем новый приватный RSA-ключ длиной 2048 бит
echo "1. Генерация приватного ключа: $KEY_FILE"
openssl genrsa -out "$KEY_FILE" 2048

# Генерируем самоподписанный X.509 сертификат из созданного ключа
# -new: создает новый запрос на сертификат
# -x509: создает самоподписанный сертификат
# -key: указывает файл приватного ключа
# -out: указывает выходной файл для сертификата
# -days: устанавливает срок действия сертификата
# -subj: устанавливает параметры субъекта сертификата без интерактивного ввода
echo "2. Генерация самоподписанного сертификата: $CERT_FILE"
openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" -days "$DAYS_VALID" -subj "$SUBJECT"

echo "---"
echo "Генерация завершена. Созданные файлы в /certs:"
ls -l /certs

# Важное примечание:
# Сертификаты генерируются внутри контейнера по пути /certs.
# Чтобы получить доступ к ним на вашей хост-машине,
# вам нужно будет использовать монтирование томов при запуске контейнера.
# Например: docker run -v /путь/на/хосте:/certs cert-generator-image