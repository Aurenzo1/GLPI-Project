#!/bin/bash
# Étape 06 (suite) : règles locales de démonstration IPS, indépendantes d'Internet
set -uo pipefail
LOG=/var/log/etape06-suricata.log
exec >>"$LOG" 2>&1
echo "=== Étape 06b (règles locales) : $(date) ==="

cat > /etc/suricata/rules/local.rules <<'EOF'
# Règles de démonstration du laboratoire GLPI sécurisé
# 1. Détection : toute ouverture de session SSH vers le serveur est journalisée
alert tcp any any -> $HOME_NET 22 (msg:"LAB - Connexion SSH vers le serveur"; flow:to_server; flags:S; sid:9000001; rev:1; classtype:not-suspicious;)
# 2. Blocage : requête web tentant de lire /etc/passwd (traversée de répertoire)
drop http any any -> $HOME_NET any (msg:"LAB - Tentative de lecture de /etc/passwd bloquee"; flow:to_server; http.uri; content:"/etc/passwd"; nocase; sid:9000002; rev:1; classtype:web-application-attack;)
# 3. Blocage : ping (ICMP echo) vers le serveur
drop icmp any any -> $HOME_NET any (msg:"LAB - Ping vers le serveur bloque par l'IPS"; itype:8; sid:9000003; rev:1; classtype:not-suspicious;)
EOF

# Charger local.rules en plus des règles ET (default-rule-path = /var/lib/suricata/rules)
if ! grep -q 'local.rules' /etc/suricata/suricata.yaml; then
  sed -i 's|^\(\s*\)- suricata.rules|\1- suricata.rules\n\1- /etc/suricata/rules/local.rules|' /etc/suricata/suricata.yaml
fi
grep -n -A3 '^rule-files:' /etc/suricata/suricata.yaml
suricata -T -c /etc/suricata/suricata.yaml 2>&1 | tail -n 1
systemctl restart suricata
sleep 12
echo "suricata : $(systemctl is-active suricata)"
grep -m1 'rules successfully loaded' /var/log/suricata/suricata.log || journalctl -u suricata --no-pager -n 3 | cut -c1-160
echo "=== Étape 06b prête : $(date) ==="
