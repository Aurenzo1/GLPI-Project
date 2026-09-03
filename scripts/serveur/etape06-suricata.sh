#!/bin/bash
# Étape 06 : Suricata en mode IPS (NFQUEUE) sur srv-glpi
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/etape06-suricata.log
exec >>"$LOG" 2>&1
echo "=== Étape 06 démarrée : $(date) ==="

echo "--- dépôt officiel et installation"
apt-get install -y -q software-properties-common >/dev/null
add-apt-repository -y ppa:oisf/suricata-stable >/dev/null 2>&1
apt-get update -q >/dev/null
apt-get install -y -q suricata jq
suricata -V

echo "--- suricata.yaml : HOME_NET = LAN + tunnel VPN"
cp -n /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.orig
sed -i 's|^\(\s*\)HOME_NET: "\[.*\]"|\1HOME_NET: "[192.168.1.0/24,10.8.0.0/24]"|' /etc/suricata/suricata.yaml
grep -m1 'HOME_NET:' /etc/suricata/suricata.yaml

echo "--- règles Emerging Threats Open"
suricata-update 2>&1 | tail -n 3

echo "--- validation de la configuration"
suricata -T -c /etc/suricata/suricata.yaml 2>&1 | tail -n 2

echo "--- mode IPS : NFQUEUE 0"
# Le service livré par le dépôt lance suricata en af-packet ; on force le mode nfqueue via un override systemd
mkdir -p /etc/systemd/system/suricata.service.d
cat > /etc/systemd/system/suricata.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/suricata -c /etc/suricata/suricata.yaml --pidfile /run/suricata.pid -q 0 -D -vvv
EOF
if [ -f /etc/default/suricata ]; then
  sed -i 's/^LISTENMODE=.*/LISTENMODE=nfqueue/; s/^NFQUEUE=.*/NFQUEUE=0/' /etc/default/suricata
fi
systemctl daemon-reload

echo "--- renvoi du trafic vers NFQUEUE avant les règles UFW (persistant)"
if ! grep -q 'NFQUEUE --queue-num 0' /etc/ufw/before.rules; then
  cp /etc/ufw/before.rules /etc/ufw/before.rules.orig
  sed -i '/^-A ufw-before-input -i lo -j ACCEPT/a -A ufw-before-input -j NFQUEUE --queue-num 0 --queue-bypass' /etc/ufw/before.rules
  sed -i '/^-A ufw-before-output -o lo -j ACCEPT/a -A ufw-before-output -j NFQUEUE --queue-num 0 --queue-bypass' /etc/ufw/before.rules
fi
grep -n 'NFQUEUE' /etc/ufw/before.rules

systemctl enable --now suricata
sleep 8
ufw reload
sleep 5
systemctl is-active suricata
iptables -S | grep NFQUEUE

echo "--- test 1 : détection (signature 2100498)"
sleep 10
curl -s --max-time 15 http://testmynids.org/uid/index.html || true
sleep 5
grep -m2 '2100498' /var/log/suricata/fast.log || echo "(pas encore d'alerte)"

echo "--- test 2 : blocage de la même signature"
grep -q '^2100498' /etc/suricata/drop.conf 2>/dev/null || echo '2100498' >> /etc/suricata/drop.conf
suricata-update 2>&1 | tail -n 1
systemctl restart suricata
sleep 12
systemctl is-active suricata
curl -s --max-time 10 http://testmynids.org/uid/index.html ; echo "code retour curl : $? (28 = timeout attendu)"
sleep 3
jq -c 'select(.event_type=="drop" or (.event_type=="alert" and .alert.signature_id==2100498)) | {timestamp, event_type, sig: .alert.signature, action: .alert.action}' /var/log/suricata/eve.json | tail -n 3
echo "=== Étape 06 terminée : $(date) ==="
