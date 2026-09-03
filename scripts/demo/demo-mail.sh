#!/bin/bash
# Plan 6 : un mail devient un ticket
SUJET="${1:-Redemarrage en boucle - bureau 7}"
echo ">>> Envoi du mail de demande : $SUJET"
echo "Bonjour, mon poste redemarre en boucle depuis ce matin. Merci de votre aide." | mail -s "$SUJET" -a "From: normal@srv-glpi.local" support@localhost
sleep 2
echo ">>> Releve de la boite par GLPI (collecteur mailgate)"
sudo mysql glpi -e "UPDATE glpi_crontasks SET lastrun=NULL WHERE name=\"mailgate\";"
sudo -u www-data php /var/www/glpi/front/cron.php mailgate
sleep 2
echo ">>> Derniers tickets"
sudo mysql glpi -e "SELECT t.id, t.name AS titre, r.name AS source, u.name AS demandeur, t.date FROM glpi_tickets t JOIN glpi_requesttypes r ON r.id=t.requesttypes_id JOIN glpi_users u ON u.id=t.users_id_recipient ORDER BY t.id DESC LIMIT 3;"
