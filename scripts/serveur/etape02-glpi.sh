#!/bin/bash
# Étape 02 du guide : serveur GLPI (LAMP + MariaDB + GLPI en HTTPS) sur srv-glpi
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/etape02-glpi.log
exec >>"$LOG" 2>&1
echo "=== Étape 02 démarrée : $(date) ==="

# --- Mot de passe de la base : généré une fois, conservé dans /root/glpi-db.env (600)
if sudo test -f /root/glpi-db.env; then
  DBPASS=$(sudo sed -n 's/^DBPASS=//p' /root/glpi-db.env)
else
  DBPASS=$(openssl rand -hex 12)
  printf 'DBNAME=glpi\nDBUSER=glpi\nDBPASS=%s\n' "$DBPASS" | sudo tee /root/glpi-db.env >/dev/null
  sudo chmod 600 /root/glpi-db.env
fi

# --- 1. Pile LAMP
echo "--- apt : Apache, PHP, MariaDB"
sudo apt-get update -q
sudo apt-get install -y -q apache2 mariadb-server php libapache2-mod-php \
  php-mysql php-curl php-gd php-intl php-ldap php-xml php-mbstring \
  php-zip php-bz2 php-bcmath php-apcu php-cli curl wget jq
sudo apt-get install -y -q php-imap || echo "php-imap indisponible, on continue"

# --- 2. MariaDB : équivalent non interactif de mysql_secure_installation
echo "--- MariaDB : sécurisation et base glpi"
sudo mysql <<SQL
DELETE FROM mysql.global_priv WHERE User='';
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'glpi'@'localhost' IDENTIFIED BY '${DBPASS}';
ALTER USER 'glpi'@'localhost' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO 'glpi'@'localhost';
FLUSH PRIVILEGES;
SQL
sudo mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | sudo mysql mysql

# --- 3. GLPI : dernière version stable
echo "--- GLPI : téléchargement"
VER=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | jq -r .tag_name)
echo "Version GLPI : $VER"
if [ ! -d /var/www/glpi ]; then
  cd /tmp
  wget -q "https://github.com/glpi-project/glpi/releases/download/$VER/glpi-$VER.tgz"
  sudo tar -xzf "glpi-$VER.tgz" -C /var/www/
  rm -f "glpi-$VER.tgz"
fi
sudo chown -R www-data:www-data /var/www/glpi

# --- 4. Certificat auto-signé + vhost HTTPS (racine web = public/)
echo "--- Apache : certificat et hôte virtuel"
if [ ! -f /etc/ssl/certs/glpi.crt ]; then
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/glpi.key -out /etc/ssl/certs/glpi.crt \
    -subj "/CN=glpi.local" -addext "subjectAltName=DNS:glpi.local,IP:192.168.1.10,IP:10.8.0.1" 2>/dev/null
fi
sudo tee /etc/apache2/sites-available/glpi.conf >/dev/null <<'EOF'
<VirtualHost *:80>
    ServerName glpi.local
    Redirect permanent / https://glpi.local/
</VirtualHost>

<VirtualHost *:443>
    ServerName glpi.local
    ServerAlias 192.168.1.10 10.8.0.1
    DocumentRoot /var/www/glpi/public

    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/glpi.crt
    SSLCertificateKeyFile /etc/ssl/private/glpi.key

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    <Directory /var/www/glpi/public>
        Require all granted
        RewriteEngine On
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>

    ErrorLog  ${APACHE_LOG_DIR}/glpi_error.log
    CustomLog ${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
EOF
sudo a2enmod -q rewrite ssl headers
sudo a2ensite -q glpi
sudo a2dissite -q 000-default || true
PHPINI=$(ls /etc/php/*/apache2/php.ini | head -n1)
sudo sed -i 's/^;\?session.cookie_httponly.*/session.cookie_httponly = On/' "$PHPINI"
sudo sed -i 's/^;\?session.cookie_secure.*/session.cookie_secure = On/' "$PHPINI"
sudo sed -i 's/^;\?session.cookie_samesite.*/session.cookie_samesite = Lax/' "$PHPINI"
sudo sed -i 's/^upload_max_filesize.*/upload_max_filesize = 20M/; s/^post_max_size.*/post_max_size = 20M/' "$PHPINI"
sudo apache2ctl configtest
sudo systemctl restart apache2

# --- 5. Installation de la base GLPI en ligne de commande
echo "--- GLPI : installation de la base"
cd /var/www/glpi
if ! sudo test -f config/config_db.php; then
  sudo -u www-data php bin/console db:install \
    --db-host=localhost --db-name=glpi --db-user=glpi --db-password="$DBPASS" \
    --default-language=fr_FR --no-interaction --force
fi
sudo rm -f /var/www/glpi/install/install.php
sudo chmod 640 /var/www/glpi/config/config_db.php
sudo chown -R www-data:www-data /var/www/glpi

# --- 6. Vérifications
echo "--- Vérifications"
sudo -u www-data php bin/console glpi:system:check_requirements --no-interaction | tail -n 25 || true
echo "HTTP  : $(curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}' http://localhost/)"
echo "HTTPS : $(curl -sk -o /dev/null -w '%{http_code}' https://localhost/)"
curl -sk https://localhost/ | grep -o '<title>[^<]*</title>' | head -n1
echo "=== Étape 02 terminée : $(date) ==="
