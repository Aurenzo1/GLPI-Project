#!/bin/bash
# Étape 09 : messagerie locale (Postfix + Dovecot IMAP) et collecteur de mails GLPI sur srv-glpi
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/etape09-mail.log
exec >>"$LOG" 2>&1
echo "=== Étape 09 démarrée : $(date) ==="

echo "--- Postfix (local uniquement) + Dovecot IMAP + mailx"
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string srv-glpi.local" | debconf-set-selections
apt-get install -y -q postfix dovecot-imapd bsd-mailx >/dev/null
postconf -e 'myhostname = srv-glpi.local' 'inet_interfaces = loopback-only' 'mydestination = $myhostname, srv-glpi, localhost.localdomain, localhost' 'inet_protocols = ipv4'
systemctl restart postfix

echo "--- compte système support (boîte relevée par GLPI)"
if ! id support >/dev/null 2>&1; then
  adduser --disabled-login --gecos 'Boite support' support >/dev/null
fi
if [ ! -f /root/mail-support.env ]; then
  MP=$(openssl rand -hex 10)
  echo "support:$MP" | chpasswd
  printf 'MAILUSER=support\nMAILPASS=%s\n' "$MP" > /root/mail-support.env
  chmod 600 /root/mail-support.env
fi
MP=$(sed -n 's/^MAILPASS=//p' /root/mail-support.env)

echo "--- Dovecot : IMAP en clair autorisé sur localhost seulement"
sed -i 's/^#\?disable_plaintext_auth.*/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's|^#\?mail_location.*|mail_location = mbox:~/mail:INBOX=/var/mail/%u|' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#\?listen = .*/listen = 127.0.0.1/' /etc/dovecot/dovecot.conf
grep -q '^listen = 127.0.0.1' /etc/dovecot/dovecot.conf || echo 'listen = 127.0.0.1' >> /etc/dovecot/dovecot.conf
systemctl restart dovecot
ss -ltn | grep ':143 ' || true

echo "--- test IMAP local"
printf 'a1 LOGIN support %s\r\na2 LOGOUT\r\n' "$MP" | timeout 5 nc -q1 127.0.0.1 143 | grep -E 'a1 (OK|NO)' || true

echo "--- collecteur GLPI"
cd /var/www/glpi
mysql glpi <<SQL
INSERT INTO glpi_mailcollectors (name, host, login, passwd, is_active, filesize_max, date_creation, date_mod)
SELECT 'Support par mail', '{localhost:143/imap/notls}INBOX', 'support', '${MP}', 1, 2097152, NOW(), NOW()
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM glpi_mailcollectors WHERE name='Support par mail');
UPDATE glpi_mailcollectors SET host='{localhost:143/imap/notls}INBOX', login='support', passwd='${MP}', is_active=1 WHERE name='Support par mail';
UPDATE glpi_crontasks SET mode=2, frequency=120, state=1 WHERE name='mailgate';
SELECT id, name, host, login, is_active FROM glpi_mailcollectors;
SELECT name, mode, frequency, state FROM glpi_crontasks WHERE name='mailgate';
SQL
# GLPI chiffre les mots de passe des collecteurs : on repasse par l'API PHP pour le stocker au bon format
sudo -u www-data php -r '
define("GLPI_ROOT", "/var/www/glpi");
include GLPI_ROOT . "/inc/includes.php";
$mc = new MailCollector();
$mc->getFromDBByCrit(["name" => "Support par mail"]);
$mc->update(["id" => $mc->getID(), "passwd" => getenv("MP")]);
echo "collecteur mis a jour (id " . $mc->getID() . ")\n";
' MP="$MP" 2>&1 | tail -n 2 || true

echo "--- cron système pour les actions automatiques GLPI"
echo '* * * * * www-data /usr/bin/php /var/www/glpi/front/cron.php >/dev/null 2>&1' > /etc/cron.d/glpi
chmod 644 /etc/cron.d/glpi

echo "--- utilisateur GLPI 'normal' : adresse mail correspondant à l'expéditeur"
mysql glpi <<'SQL'
INSERT INTO glpi_useremails (users_id, is_default, email)
SELECT u.id, 1, 'normal@srv-glpi.local' FROM glpi_users u WHERE u.name='normal'
AND NOT EXISTS (SELECT 1 FROM glpi_useremails e WHERE e.users_id=u.id);
SQL

echo "--- test de bout en bout : mail -> ticket"
echo "Bonjour, mon écran reste noir au démarrage. Merci de votre aide." | mail -s "Panne écran salle 2" -r normal@srv-glpi.local support@localhost
sleep 3
sudo -u www-data php /var/www/glpi/front/cron.php mailgate 2>&1 | tail -n 3 || true
sleep 2
mysql glpi -e "SELECT id, name, users_id_recipient, requesttypes_id, date FROM glpi_tickets ORDER BY id DESC LIMIT 3;"
mysql glpi -e "SELECT t.name AS ticket, r.name AS origine FROM glpi_tickets t JOIN glpi_requesttypes r ON r.id=t.requesttypes_id ORDER BY t.id DESC LIMIT 1;"
echo "=== Étape 09 terminée : $(date) ==="
