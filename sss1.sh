# Подключение репозитория EPEL и Remi для актуальной версии PHP
sudo yum install -y epel-release
sudo yum install -y https://rpms.remirepo.net/enterprise/remi-release-7.rpm
sudo yum-config-manager --enable remi-php74  # или remi-php80 / php81

# Установка Apache, PHP и необходимых модулей
sudo yum install -y httpd php php-pdo php-mysqlnd php-common php-openssl

# Запуск и добавление веб-сервера в автозагрузку
sudo systemctl start httpd
sudo systemctl enable httpd
